import 'dart:io';

import 'package:drift/native.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:test/test.dart';

void main() {
  late EleenDatabase db;
  late EngineCoordinator coordinator;
  late EleenServer server;
  late Uri base;
  const pin = '1234';

  setUp(() async {
    db = EleenDatabase(NativeDatabase.memory());
    await db.saveSettings(const Settings(parentPin: pin));
    coordinator = EngineCoordinator(
      db: db,
      engine: TimeEngine(clock: SystemClock()),
    );
    server = EleenServer(coordinator: coordinator);
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
    base = Uri.parse('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await server.stop();
    await db.close();
  });

  /// A fresh client that has paired against the running server (token stored).
  Future<EleenClient> pairedClient() async {
    final client = EleenClient(base: base);
    final nonce = PairingCodec.newNonce();
    server.registerNonce(nonce);
    await client.pair(nonce);
    return client;
  }

  group('pair', () {
    test('stores the issued token on the client', () async {
      final client = EleenClient(base: base);
      final nonce = PairingCodec.newNonce();
      server.registerNonce(nonce);

      final token = await client.pair(nonce);

      expect(token, isNotEmpty);
      expect(client.token, token);
    });

    test('the stored token authorizes subsequent calls', () async {
      final client = await pairedClient();

      // No token passed by hand: the client must use the paired one.
      final st = await client.state();
      expect(st.profiles, isEmpty);
    });

    test('against a stopped server throws EleenOffline', () async {
      final client = EleenClient(base: base);
      await server.stop();

      await expectLater(client.pair('nonce'), throwsA(isA<EleenOffline>()));
    });
  });

  group('state', () {
    test('parses the wire format into a domain TvState', () async {
      final client = await pairedClient();
      final maya = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );
      final leo = await coordinator.createProfile(
        name: 'Leo',
        avatar: 'bear',
        allowance: AllowanceMinutes.fortyFive,
      );
      await db.saveSession(SessionState(
        profileId: maya.id,
        date: DateTime.now(),
        remainingSeconds: 700,
        active: true,
      ));

      final st = await client.state();

      expect(st.profiles.length, 2);
      final mayaOut = st.profiles.firstWhere((p) => p.id == maya.id);
      expect(mayaOut.name, 'Maya');
      expect(mayaOut.avatar, 'fox');
      expect(mayaOut.allowance, AllowanceMinutes.thirty);
      final leoOut = st.profiles.firstWhere((p) => p.id == leo.id);
      expect(leoOut.allowance, AllowanceMinutes.fortyFive);

      expect(st.remainingByProfile[maya.id], 700);
      expect(st.remainingByProfile[leo.id], 45 * 60);
      expect(st.activeSession?.profileId, maya.id);
      expect(st.masterLockEnabled, isFalse);
    });

    test('reflects the master lock', () async {
      final client = await pairedClient();
      await coordinator.setMasterLock(true);

      final st = await client.state();

      expect(st.masterLockEnabled, isTrue);
    });

    test('without a token surfaces EleenApiError(401)', () async {
      final client = EleenClient(base: base);

      await expectLater(
        client.state(),
        throwsA(isA<EleenApiError>().having((e) => e.status, 'status', 401)),
      );
    });

    test('against a stopped server throws EleenOffline', () async {
      final client = await pairedClient();
      await server.stop();

      await expectLater(client.state(), throwsA(isA<EleenOffline>()));
    });

    test('parses the usage block into usageByProfile', () async {
      final client = await pairedClient();
      final kid = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.fifteen,
      );
      await db.addUsedSeconds(kid.id, DateTime.now(), 1500);
      await db.addUsedSeconds(
          kid.id, DateTime.now().subtract(const Duration(days: 1)), 1800);

      final st = await client.state();

      final usage = st.usageByProfile[kid.id];
      expect(usage, isNotNull);
      expect(usage!.todaySeconds, 1500);
      expect(usage.history, hasLength(2));
      // Newest first, date-only and seconds preserved over the wire.
      expect(usage.history.first.seconds, 1500);
      expect(usage.history.last.seconds, 1800);
      expect(usage.history.last.date.day,
          DateTime.now().subtract(const Duration(days: 1)).day);
    });

    test('tolerates a state payload without usage (older server)',
        () async {
      // The wire path can't drop the key against the current server, so
      // exercise the parser directly: absence must yield an empty map, not
      // a throw.
      expect(EleenClient.parseUsage(null), isEmpty);
      expect(EleenClient.parseUsage({
        'kid-1': {
          'todaySeconds': 300,
          'history': [
            {'date': '2026-10-24', 'seconds': 300},
          ],
        },
        'kid-2': 'garbage',
        'kid-3': {
          'todaySeconds': 'not-an-int',
          'history': [
            {'date': 'nope', 'seconds': 1},
            'also-garbage',
          ],
        },
      }), {
        'kid-1': isA<ProfileUsage>()
            .having((u) => u.todaySeconds, 'todaySeconds', 300)
            .having((u) => u.history, 'history', hasLength(1)),
        // kid-2/kid-3 are malformed: skipped / defaulted, never thrown.
        'kid-3': isA<ProfileUsage>()
            .having((u) => u.todaySeconds, 'todaySeconds', 0)
            .having((u) => u.history, 'history', isEmpty),
      });
    });
  });

  group('addTime', () {
    test('adds session seconds on top of the allowance', () async {
      final client = await pairedClient();
      final profile = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      await client.addTime(profile.id, 600, pin);

      final st = await client.state();
      expect(st.remainingByProfile[profile.id], 30 * 60 + 600);
    });

    test('a wrong PIN surfaces EleenApiError(403)', () async {
      final client = await pairedClient();
      final profile = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      await expectLater(
        client.addTime(profile.id, 600, '9999'),
        throwsA(isA<EleenApiError>().having((e) => e.status, 'status', 403)),
      );
    });
  });

  group('overrideTime', () {
    test('overwrites the remaining seconds', () async {
      final client = await pairedClient();
      final profile = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      await client.overrideTime(profile.id, 1000, pin);

      final st = await client.state();
      expect(st.remainingByProfile[profile.id], 1000);
    });

    test('a wrong PIN surfaces EleenApiError(403)', () async {
      final client = await pairedClient();
      final profile = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      await expectLater(
        client.overrideTime(profile.id, 1000, 'wrong'),
        throwsA(isA<EleenApiError>().having((e) => e.status, 'status', 403)),
      );
    });
  });

  group('setMasterLock', () {
    test('locks and unlocks via the server', () async {
      final client = await pairedClient();
      final profile = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );
      await db.saveSession(SessionState(
        profileId: profile.id,
        date: DateTime.now(),
        remainingSeconds: 500,
        active: true,
      ));

      await client.setMasterLock(true, pin);

      var st = await client.state();
      expect(st.masterLockEnabled, isTrue);
      final session = await db.sessionForProfile(profile.id, DateTime.now());
      expect(session!.active, isFalse);

      await client.setMasterLock(false, pin);

      st = await client.state();
      expect(st.masterLockEnabled, isFalse);
    });

    test('a wrong PIN surfaces EleenApiError(403)', () async {
      final client = await pairedClient();

      await expectLater(
        client.setMasterLock(true, 'nope'),
        throwsA(isA<EleenApiError>().having((e) => e.status, 'status', 403)),
      );
    });
  });

  group('upsertProfile', () {
    test('parses isParent from the state payload', () async {
      final client = await pairedClient();
      final parent = await coordinator.createProfile(
        name: 'Ava',
        avatar: 'bear',
        allowance: AllowanceMinutes.thirty,
        isParent: true,
      );
      final child = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      final st = await client.state();

      expect(st.profiles.firstWhere((p) => p.id == parent.id).isParent,
          isTrue);
      expect(st.profiles.firstWhere((p) => p.id == child.id).isParent,
          isFalse);
    });

    test('creates a parent profile (isParent round-trips)', () async {
      final client = await pairedClient();

      await client.upsertProfile(
        const Profile(
          id: '',
          name: 'Ava',
          avatar: 'bear',
          allowance: AllowanceMinutes.thirty,
          isParent: true,
        ),
        pin,
      );

      final st = await client.state();
      expect(st.profiles.single.isParent, isTrue);
    });

    test('creates a profile with an empty id', () async {
      final client = await pairedClient();

      await client.upsertProfile(
        const Profile(
          id: '',
          name: 'Maya',
          avatar: 'fox',
          allowance: AllowanceMinutes.thirty,
        ),
        pin,
      );

      final st = await client.state();
      expect(st.profiles.length, 1);
      expect(st.profiles.single.name, 'Maya');
      expect(st.profiles.single.avatar, 'fox');
      expect(st.profiles.single.allowance, AllowanceMinutes.thirty);
      expect(st.profiles.single.id, isNotEmpty);
    });

    test('patches an existing profile by id', () async {
      final client = await pairedClient();
      final profile = await coordinator.createProfile(
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      await client.upsertProfile(
        Profile(
          id: profile.id,
          name: 'Maya',
          avatar: 'cat',
          allowance: AllowanceMinutes.sixty,
        ),
        pin,
      );

      final st = await client.state();
      final updated = st.profiles.single;
      expect(updated.id, profile.id);
      expect(updated.name, 'Maya');
      expect(updated.avatar, 'cat');
      expect(updated.allowance, AllowanceMinutes.sixty);
    });

    test('a wrong PIN surfaces EleenApiError(403)', () async {
      final client = await pairedClient();

      await expectLater(
        client.upsertProfile(
          const Profile(
            id: '',
            name: 'Maya',
            avatar: 'fox',
            allowance: AllowanceMinutes.thirty,
          ),
          '0000',
        ),
        throwsA(isA<EleenApiError>().having((e) => e.status, 'status', 403)),
      );
    });
  });
}
