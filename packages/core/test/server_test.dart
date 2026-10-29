import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:test/test.dart';

void main() {
  late EleenDatabase db;
  late EngineCoordinator coordinator;
  late EleenServer server;
  late int port;
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
    port = server.port;
  });

  tearDown(() async {
    await server.stop();
    await db.close();
  });

  /// Like [call] but sends [body] verbatim (for malformed-payload tests).
  Future<(int, dynamic)> callRaw(
    String method,
    String path, {
    String? body,
    String? token,
    int? onPort,
  }) async {
    final client = HttpClient();
    try {
      final req = await client.open(method, '127.0.0.1', onPort ?? port, path);
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      req.headers.contentType = ContentType.json;
      if (body != null) req.write(body);
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
    } finally {
      client.close(force: true);
    }
  }

  /// Performs a real HTTP round-trip against the server.
  /// Returns (statusCode, decoded JSON body or null).
  Future<(int, dynamic)> call(
    String method,
    String path, {
    Object? body,
    String? token,
    int? onPort,
  }) =>
      callRaw(method, path,
          body: body == null ? null : jsonEncode(body),
          token: token,
          onPort: onPort);

  /// Registers a fresh nonce on [target] and pairs against it, returning
  /// the issued token.
  Future<String> pairOn(EleenServer target, int onPort) async {
    final nonce = PairingCodec.newNonce();
    target.registerNonce(nonce);
    final client = HttpClient();
    try {
      final req =
          await client.open('POST', '127.0.0.1', onPort, '/api/pair');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'nonce': nonce}));
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      expect(res.statusCode, 200, reason: 'pairing should succeed: $text');
      return (jsonDecode(text) as Map)['token'] as String;
    } finally {
      client.close(force: true);
    }
  }

  /// Registers a fresh nonce and pairs, returning the issued token.
  Future<String> pair() => pairOn(server, port);

  /// Boots a fresh, isolated server over a fresh DB with NO parent PIN
  /// (the fresh-install shape). The caller must stop/close the returned
  /// server and db.
  Future<(EleenServer, EleenDatabase)> bootFresh() async {
    final freshDb = EleenDatabase(NativeDatabase.memory());
    final freshServer = EleenServer(
      coordinator: EngineCoordinator(
        db: freshDb,
        engine: TimeEngine(clock: SystemClock()),
      ),
    );
    await freshServer.start(address: InternetAddress.loopbackIPv4, port: 0);
    return (freshServer, freshDb);
  }

  Future<String> createProfile(
    String token, {
    String name = 'Maya',
    String avatar = 'fox',
    int allowance = 30,
    bool isParent = false,
  }) async {
    final (status, body) = await call(
      'POST',
      '/api/profiles',
      body: {
        'name': name,
        'avatar': avatar,
        'allowanceMinutes': allowance,
        'isParent': isParent,
        'pin': pin,
      },
      token: token,
    );
    expect(status, 200, reason: 'profile creation should succeed: $body');
    return (body as Map)['id'] as String;
  }

  group('PairingCodec', () {
    test('payload produces the exact eleen://pair URI', () {
      expect(
        PairingCodec.payload(host: '192.168.1.5', port: 8477, nonce: 'abc123'),
        'eleen://pair?host=192.168.1.5&port=8477&nonce=abc123',
      );
    });

    test('parse round-trips payload', () {
      final payload =
          PairingCodec.payload(host: '10.0.0.2', port: 9000, nonce: 'n-42');
      expect(
        PairingCodec.parse(payload),
        (host: '10.0.0.2', port: 9000, nonce: 'n-42'),
      );
    });

    test('parse returns null for malformed payloads', () {
      expect(PairingCodec.parse('eleen://pair'), isNull);
      expect(
        PairingCodec.parse('eleen://pair?host=h&port=notanumber&nonce=n'),
        isNull,
      );
      expect(
        PairingCodec.parse('eleen://pair?host=h&port=1'),
        isNull,
      );
      expect(
        PairingCodec.parse('http://pair?host=h&port=1&nonce=n'),
        isNull,
      );
    });

    test('newNonce returns non-empty, distinct nonces', () {
      final a = PairingCodec.newNonce();
      final b = PairingCodec.newNonce();
      expect(a, isNotEmpty);
      expect(a, isNot(b));
    });
  });

  group('POST /api/pair', () {
    test('issues a token for a registered nonce', () async {
      final nonce = PairingCodec.newNonce();
      server.registerNonce(nonce);
      final (status, body) =
          await call('POST', '/api/pair', body: {'nonce': nonce});

      expect(status, 200);
      final token = (body as Map)['token'];
      expect(token, isA<String>());
      expect((token as String).isNotEmpty, isTrue);
    });

    test('rejects a nonce that was never registered with 401', () async {
      final (status, _) =
          await call('POST', '/api/pair', body: {'nonce': 'bogus'});
      expect(status, 401);
    });

    test('nonce is single-use: reuse returns 401', () async {
      final nonce = PairingCodec.newNonce();
      server.registerNonce(nonce);
      final (first, _) =
          await call('POST', '/api/pair', body: {'nonce': nonce});
      expect(first, 200);

      final (second, _) =
          await call('POST', '/api/pair', body: {'nonce': nonce});
      expect(second, 401);
    });
  });

  group('Bearer token auth', () {
    test('GET /api/state without a token returns 401', () async {
      final (status, _) = await call('GET', '/api/state');
      expect(status, 401);
    });

    test('GET /api/state with a wrong token returns 401', () async {
      final (status, _) = await call('GET', '/api/state', token: 'nope');
      expect(status, 401);
    });

    test('POST /api/profiles without a token returns 401', () async {
      final (status, _) = await call('POST', '/api/profiles', body: {
        'name': 'Maya',
        'avatar': 'fox',
        'allowanceMinutes': 30,
        'pin': pin,
      });
      expect(status, 401);
    });

    test('a paired token authorizes requests', () async {
      final token = await pair();
      final (status, _) = await call('GET', '/api/state', token: token);
      expect(status, 200);
    });
  });

  group('GET /api/state', () {
    test('JSON shape matches the contract exactly', () async {
      final token = await pair();
      final id1 = await createProfile(token,
          name: 'Maya', avatar: 'fox', allowance: 30);
      final id2 = await createProfile(
          token, name: 'Leo', avatar: 'bear', allowance: 45);

      final (status, body) = await call('GET', '/api/state', token: token);
      expect(status, 200);

      final json = body as Map;
      expect(
        (json).keys.toSet(),
        {'profiles', 'activeProfileId', 'remainingByProfile', 'masterLockEnabled', 'parentPinSet', 'overlayPermissionGranted', 'usage'},
      );
      // The TV app publishes its live SYSTEM_ALERT_WINDOW probe result
      // here (default granted — the coordinator flag no test has flipped).
      expect(json['overlayPermissionGranted'], isTrue);
      // Every current profile has a usage entry (v1.1 D): todaySeconds plus
      // the 14-day-capped history of {date, seconds} rows.
      expect((json['usage'] as Map).keys.toSet(), {id1, id2});
      final mayaUsage = json['usage'][id1] as Map;
      expect(mayaUsage['todaySeconds'], 0);
      expect(mayaUsage['history'], isEmpty);

      final profiles = json['profiles'] as List;
      expect(profiles.length, 2);
      expect(
        (profiles.first as Map).keys.toSet(),
        {'id', 'name', 'avatar', 'allowanceMinutes', 'isParent'},
      );

      final maya =
          profiles.firstWhere((p) => (p as Map)['id'] == id1) as Map;
      expect(maya['name'], 'Maya');
      expect(maya['avatar'], 'fox');
      expect(maya['allowanceMinutes'], 30);
      expect(maya['isParent'], isFalse);

      // No session yet: remaining is the full allowance in session seconds.
      expect(json['remainingByProfile'][id1], 30 * 60);
      expect(json['activeProfileId'], isNull);
      expect(json['masterLockEnabled'], isFalse);
      expect(json['parentPinSet'], isTrue); // setUp seeds a PIN
    });

    test('reports parentPinSet false on a fresh install', () async {
      final (freshServer, freshDb) = await bootFresh();
      try {
        final token = await pairOn(freshServer, freshServer.port);
        final (_, body) = await call('GET', '/api/state',
            token: token, onPort: freshServer.port);
        expect((body as Map)['parentPinSet'], isFalse);
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });

    test('reflects an active session for a current profile', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      await db.saveSession(SessionState(
        profileId: id,
        date: DateTime.now(),
        remainingSeconds: 700,
        active: true,
      ));

      final (_, body) = await call('GET', '/api/state', token: token);
      final json = body as Map;
      expect(json['activeProfileId'], id);
      expect(json['remainingByProfile'][id], 700);
    });

    test('never surfaces sessions of deleted profiles', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      await db.saveSession(SessionState(
        profileId: id,
        date: DateTime.now(),
        remainingSeconds: 111,
        active: true,
      ));
      // Orphan the session row by deleting the profile behind the server's
      // back (Task 4 ruling: deleteProfile leaves orphaned Sessions rows).
      await db.deleteProfile(id);

      final (_, body) = await call('GET', '/api/state', token: token);
      final json = body as Map;
      expect(json['profiles'], isEmpty);
      expect(json['remainingByProfile'], isEmpty);
      expect(json['activeProfileId'], isNull);
    });
  });

  group('POST /api/profiles', () {
    test('rejects a wrong PIN with 403', () async {
      final token = await pair();
      final (status, _) = await call('POST', '/api/profiles', body: {
        'name': 'Maya',
        'avatar': 'fox',
        'allowanceMinutes': 30,
        'pin': '9999',
      }, token: token);
      expect(status, 403);
    });

    test('rejects an invalid allowance with 400', () async {
      final token = await pair();
      final (status, _) = await call('POST', '/api/profiles', body: {
        'name': 'Maya',
        'avatar': 'fox',
        'allowanceMinutes': 20,
        'pin': pin,
      }, token: token);
      expect(status, 400);
    });

    test('creates the profile and it appears in state', () async {
      final token = await pair();
      final id = await createProfile(token,
          name: 'Maya', avatar: 'fox', allowance: 60);

      final (_, body) = await call('GET', '/api/state', token: token);
      final profiles = (body as Map)['profiles'] as List;
      expect(profiles.length, 1);
      expect((profiles.single as Map)['id'], id);
      expect((profiles.single as Map)['allowanceMinutes'], 60);
      expect((profiles.single as Map)['isParent'], isFalse);
    });

    test('isParent defaults to false when the field is absent', () async {
      final token = await pair();
      final (status, _) = await call('POST', '/api/profiles',
          body: {'name': 'Maya', 'avatar': 'fox',
              'allowanceMinutes': 30, 'pin': pin},
          token: token);
      expect(status, 200);

      final (_, body) = await call('GET', '/api/state', token: token);
      final profile = ((body as Map)['profiles'] as List).single as Map;
      expect(profile['isParent'], isFalse);
    });

    test('creates a parent profile when isParent is true', () async {
      final token = await pair();
      final (status, created) = await call('POST', '/api/profiles', body: {
        'name': 'Ava',
        'avatar': 'bear',
        'allowanceMinutes': 30,
        'isParent': true,
        'pin': pin,
      }, token: token);
      expect(status, 200);
      expect((created as Map)['isParent'], isTrue);

      final (_, state) = await call('GET', '/api/state', token: token);
      final profile = ((state as Map)['profiles'] as List).single as Map;
      expect(profile['isParent'], isTrue);
    });

    test('rejects a non-bool isParent with 400', () async {
      final token = await pair();
      final (status, _) = await call('POST', '/api/profiles', body: {
        'name': 'Ava',
        'avatar': 'bear',
        'allowanceMinutes': 30,
        'isParent': 'yes',
        'pin': pin,
      }, token: token);
      expect(status, 400);
    });
  });

  group('PATCH /api/profiles/{id}', () {
    test('rejects a wrong PIN with 403', () async {
      final token = await pair();
      final id = await createProfile(token);
      final (status, _) = await call(
        'PATCH',
        '/api/profiles/$id',
        body: {'name': 'New', 'pin': '9999'},
        token: token,
      );
      expect(status, 403);
    });

    test('updates only the provided fields', () async {
      final token = await pair();
      final id = await createProfile(token,
          name: 'Maya', avatar: 'fox', allowance: 30);

      final (status, body) = await call(
        'PATCH',
        '/api/profiles/$id',
        body: {'avatar': 'cat', 'allowanceMinutes': 45, 'pin': pin},
        token: token,
      );
      expect(status, 200);

      final (_, state) = await call('GET', '/api/state', token: token);
      final p = ((state as Map)['profiles'] as List).single as Map;
      expect(p['id'], id);
      expect(p['name'], 'Maya'); // untouched
      expect(p['avatar'], 'cat');
      expect(p['allowanceMinutes'], 45);
      expect((body as Map)['avatar'], 'cat');
    });

    test('updates isParent when provided', () async {
      final token = await pair();
      final id = await createProfile(token, name: 'Maya', avatar: 'fox');

      final (status, body) = await call(
        'PATCH',
        '/api/profiles/$id',
        body: {'isParent': true, 'pin': pin},
        token: token,
      );
      expect(status, 200);
      expect((body as Map)['isParent'], isTrue);

      final (_, state) = await call('GET', '/api/state', token: token);
      final p = ((state as Map)['profiles'] as List).single as Map;
      expect(p['isParent'], isTrue);
    });

    test('rejects a non-bool isParent with 400', () async {
      final token = await pair();
      final id = await createProfile(token);

      final (status, _) = await call(
        'PATCH',
        '/api/profiles/$id',
        body: {'isParent': 1, 'pin': pin},
        token: token,
      );
      expect(status, 400);
    });

    test('returns 404 for an unknown profile', () async {
      final token = await pair();
      final (status, _) = await call(
        'PATCH',
        '/api/profiles/no-such-id',
        body: {'name': 'X', 'pin': pin},
        token: token,
      );
      expect(status, 404);
    });
  });

  group('POST /api/time', () {
    test('rejects missing token with 401', () async {
      final (status, _) = await call('POST', '/api/time', body: {
        'profileId': 'p',
        'addSeconds': 60,
        'pin': pin,
      });
      expect(status, 401);
    });

    test('rejects a wrong PIN with 403', () async {
      final token = await pair();
      await createProfile(token);
      final (status, _) = await call('POST', '/api/time', body: {
        'profileId': 'p',
        'addSeconds': 60,
        'pin': '0000',
      }, token: token);
      expect(status, 403);
    });

    test('add-time result math (session seconds on top of full allowance)',
        () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);

      final (status, body) = await call('POST', '/api/time', body: {
        'profileId': id,
        'addSeconds': 600,
        'pin': pin,
      }, token: token);

      expect(status, 200);
      expect((body as Map)['profileId'], id);
      // Full 30-min allowance (1800 s) + 600 added session seconds.
      expect(body['remainingSeconds'], 2400);
    });

    test('the added time shows up in state', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      await call('POST', '/api/time', body: {
        'profileId': id,
        'addSeconds': 600,
        'pin': pin,
      }, token: token);

      final (_, state) = await call('GET', '/api/state', token: token);
      expect((state as Map)['remainingByProfile'][id], 2400);
    });

    test('returns 404 for an unknown profile', () async {
      final token = await pair();
      final (status, _) = await call('POST', '/api/time', body: {
        'profileId': 'ghost',
        'addSeconds': 60,
        'pin': pin,
      }, token: token);
      expect(status, 404);
    });
  });

  group('PUT /api/time/{id}', () {
    test('rejects missing token with 401 and wrong PIN with 403', () async {
      final token = await pair();
      final id = await createProfile(token);

      final (noToken, _) = await call(
        'PUT',
        '/api/time/$id',
        body: {'remainingSeconds': 100, 'pin': pin},
      );
      expect(noToken, 401);

      final (badPin, _) = await call(
        'PUT',
        '/api/time/$id',
        body: {'remainingSeconds': 100, 'pin': 'wrong'},
        token: token,
      );
      expect(badPin, 403);
    });

    test('overrides the remaining seconds', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);

      final (status, body) = await call(
        'PUT',
        '/api/time/$id',
        body: {'remainingSeconds': 1000, 'pin': pin},
        token: token,
      );
      expect(status, 200);
      expect((body as Map)['remainingSeconds'], 1000);

      final (_, state) = await call('GET', '/api/state', token: token);
      expect((state as Map)['remainingByProfile'][id], 1000);
    });
  });

  group('POST /api/lock', () {
    test('rejects missing token with 401 and wrong PIN with 403', () async {
      final (noToken, _) =
          await call('POST', '/api/lock', body: {'enabled': true, 'pin': pin});
      expect(noToken, 401);

      final token = await pair();
      final (badPin, _) = await call('POST', '/api/lock',
          body: {'enabled': true, 'pin': 'nope'}, token: token);
      expect(badPin, 403);
    });

    test('enables the master lock and marks the session inactive', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      await db.saveSession(SessionState(
        profileId: id,
        date: DateTime.now(),
        remainingSeconds: 500,
        active: true,
      ));

      final (status, _) = await call('POST', '/api/lock',
          body: {'enabled': true, 'pin': pin}, token: token);
      expect(status, 200);

      final (_, state) = await call('GET', '/api/state', token: token);
      expect((state as Map)['masterLockEnabled'], isTrue);

      final today = DateTime.now();
      final session = await db.sessionForProfile(id, today);
      expect(session, isNotNull);
      expect(session!.active, isFalse);
      expect(session.remainingSeconds, 500); // lock preserves remaining
    });

    test('unlock re-activates the locked-away session', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      await db.saveSession(SessionState(
        profileId: id,
        date: DateTime.now(),
        remainingSeconds: 500,
        active: true,
      ));

      await call('POST', '/api/lock',
          body: {'enabled': true, 'pin': pin}, token: token);
      final (status, _) = await call('POST', '/api/lock',
          body: {'enabled': false, 'pin': pin}, token: token);
      expect(status, 200);

      final session = await db.sessionForProfile(id, DateTime.now());
      expect(session!.active, isTrue);
      expect(session.remainingSeconds, 500);
    });
  });

  group('master lock keeps the single-active invariant', () {
    test('unlock reactivates only the profile that was active at lock time',
        () async {
      final token = await pair();
      final idA = await createProfile(token, name: 'A', allowance: 30);
      final idB = await createProfile(token, name: 'B', allowance: 30);
      await db.saveSession(SessionState(
        profileId: idA,
        date: DateTime.now(),
        remainingSeconds: 900,
        active: true,
      ));
      await db.saveSession(SessionState(
        profileId: idB,
        date: DateTime.now(),
        remainingSeconds: 700,
        active: false,
      ));

      await call('POST', '/api/lock',
          body: {'enabled': true, 'pin': pin}, token: token);
      final locked = await coordinator.state();
      expect(locked.masterLockEnabled, isTrue);
      expect(locked.activeSession, isNull);

      await call('POST', '/api/lock',
          body: {'enabled': false, 'pin': pin}, token: token);
      final unlocked = await coordinator.state();
      expect(unlocked.masterLockEnabled, isFalse);
      // Exactly one active session, and it is the same child that was
      // ticking before the lock.
      expect(unlocked.activeSession, isNotNull);
      expect(unlocked.activeSession!.profileId, idA);
      expect(unlocked.activeSession!.remainingSeconds, 900);
      final b = await db.sessionForProfile(idB, DateTime.now());
      expect(b!.active, isFalse, reason: 'the other child must stay parked');
    });

    test('lock with no active session -> unlock restores none', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      await db.saveSession(SessionState(
        profileId: id,
        date: DateTime.now(),
        remainingSeconds: 500,
        active: false,
      ));

      await call('POST', '/api/lock',
          body: {'enabled': true, 'pin': pin}, token: token);
      await call('POST', '/api/lock',
          body: {'enabled': false, 'pin': pin}, token: token);

      final st = await coordinator.state();
      expect(st.masterLockEnabled, isFalse);
      expect(st.activeSession, isNull);
    });
  });

  group('PUT /api/pin', () {
    test('requires the bearer token (401)', () async {
      final (status, _) = await call('PUT', '/api/pin', body: {'pin': '4321'});
      expect(status, 401);
    });

    test('sets the PIN when none is set, without a currentPin', () async {
      final (freshServer, freshDb) = await bootFresh();
      try {
        final token = await pairOn(freshServer, freshServer.port);
        final (status, _) = await call('PUT', '/api/pin',
            body: {'pin': '4321'}, token: token, onPort: freshServer.port);
        expect(status, 200);
        final settings = await freshDb.getSettings();
        expect(settings.parentPin, '4321');
        expect(settings.token, token, reason: 'pairing token is preserved');
        expect(settings.masterLockEnabled, isFalse);
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });

    test('changes the PIN with the correct currentPin', () async {
      final token = await pair();
      final (status, _) = await call('PUT', '/api/pin',
          body: {'pin': '5678', 'currentPin': pin}, token: token);
      expect(status, 200);
      expect((await db.getSettings()).parentPin, '5678');
    });

    test('rejects a wrong currentPin with 403 and changes nothing', () async {
      final token = await pair();
      final (status, _) = await call('PUT', '/api/pin',
          body: {'pin': '5678', 'currentPin': '0000'}, token: token);
      expect(status, 403);
      expect((await db.getSettings()).parentPin, pin);
    });

    test('rejects a missing currentPin with 403 when a PIN is set',
        () async {
      final token = await pair();
      final (status, _) = await call('PUT', '/api/pin',
          body: {'pin': '5678'}, token: token);
      expect(status, 403);
      expect((await db.getSettings()).parentPin, pin);
    });

    test('rejects an empty pin with 400', () async {
      final token = await pair();
      final (status, _) = await call('PUT', '/api/pin',
          body: {'pin': ''}, token: token);
      expect(status, 400);
    });

    test('rejects a too-short pin with 400', () async {
      final token = await pair();
      final (status, _) = await call('PUT', '/api/pin',
          body: {'pin': '123'}, token: token);
      expect(status, 400);
    });

    test('rejects a too-long pin with 400', () async {
      final token = await pair();
      final (status, _) = await call('PUT', '/api/pin',
          body: {'pin': '12345'}, token: token);
      expect(status, 400,
          reason: 'the exactly-4 rule must hold for API clients too, not '
              'just the shipped UI');
      // And nothing was persisted.
      expect((await db.getSettings()).parentPin, pin);
    });
  });

  group('fresh-install client path', () {
    test('pair -> setPin -> create profile -> addTime with that PIN succeeds',
        () async {
      final (freshServer, freshDb) = await bootFresh();
      try {
        final nonce = PairingCodec.newNonce();
        freshServer.registerNonce(nonce);
        final client =
            EleenClient(base: Uri.parse('http://127.0.0.1:${freshServer.port}'));

        await client.pair(nonce);

        // Fresh install: the TV reports no PIN yet...
        final before = await client.state();
        expect(before.parentPinSet, isFalse);
        expect(before.profiles, isEmpty);

        // ...so the pairing phone provisions one...
        await client.setPin('9876');
        expect((await client.state()).parentPinSet, isTrue);

        // ...creates the first profile with that PIN...
        await client.upsertProfile(
          const Profile(
            id: '',
            name: 'Maya',
            avatar: 'M',
            allowance: AllowanceMinutes.fifteen,
          ),
          '9876',
        );
        final st = await client.state();
        expect(st.profiles, hasLength(1));
        final id = st.profiles.single.id;
        expect(id, isNotEmpty);

        // ...and reaches an unlock-gated mutation with it: add-time succeeds
        // on top of the full 15-minute allowance.
        await client.addTime(id, 600, '9876');
        final after = await client.state();
        expect(after.remainingByProfile[id], 15 * 60 + 600);

        // The gate is real: a wrong PIN is still a 403.
        await expectLater(
          client.addTime(id, 60, '0000'),
          throwsA(isA<EleenApiError>()
              .having((e) => e.status, 'status', 403)),
        );
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });
  });

  group('threshold re-arming', () {
    test('add-time clears fired entries below the new remaining', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);

      // Simulate a session sitting at 100 s with 300 and 900 already fired.
      await call('PUT', '/api/time/$id', body: {
        'remainingSeconds': 100,
        'pin': pin,
      }, token: token);
      coordinator.markThresholdFired(id, 300);
      coordinator.markThresholdFired(id, 900);
      expect(coordinator.firedThresholds(id), {300, 900});

      await call('POST', '/api/time', body: {
        'profileId': id,
        'addSeconds': 600,
        'pin': pin,
      }, token: token);

      // New remaining is 700: the 300 s threshold is below it and re-arms,
      // the 900 s threshold is still above and stays fired.
      expect(coordinator.firedThresholds(id), {900});
    });
  });

  group('unknown routes', () {
    test('return 404', () async {
      final token = await pair();
      final (status, _) = await call('GET', '/api/nonsense', token: token);
      expect(status, 404);
    });
  });

  group('malformed request bodies', () {
    test('invalid JSON returns 400, not 500', () async {
      final token = await pair();
      await createProfile(token, allowance: 30);
      final (status, _) = await callRaw('POST', '/api/time',
          body: 'not-json{', token: token);
      expect(status, 400);
    });

    test('a JSON array body returns 400', () async {
      final token = await pair();
      final (status, _) =
          await callRaw('POST', '/api/time', body: '[1,2]', token: token);
      expect(status, 400);
    });
  });

  group('negative values', () {
    test('negative addSeconds returns 400', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      final (status, _) = await call('POST', '/api/time', body: {
        'profileId': id,
        'addSeconds': -60,
        'pin': pin,
      }, token: token);
      expect(status, 400);
    });

    test('negative remainingSeconds returns 400', () async {
      final token = await pair();
      final id = await createProfile(token, allowance: 30);
      final (status, _) = await call('PUT', '/api/time/$id', body: {
        'remainingSeconds': -5,
        'pin': pin,
      }, token: token);
      expect(status, 400);
    });
  });

  group('start/stop lifecycle', () {
    test('starting twice throws StateError', () async {
      await expectLater(
        server.start(address: InternetAddress.loopbackIPv4, port: 0),
        throwsStateError,
      );
    });
  });

  group('optional parent PIN (no PIN set)', () {
    /// Pairs a fresh no-PIN server and creates one profile, returning
    /// (token, profileId) against the MAIN test server's helper signatures.
    Future<(String, String, EleenServer, EleenDatabase)> bootFreshWithProfile({
      int allowance = 30,
    }) async {
      final (freshServer, freshDb) = await bootFresh();
      final nonce = PairingCodec.newNonce();
      freshServer.registerNonce(nonce);
      final client =
          EleenClient(base: Uri.parse('http://127.0.0.1:${freshServer.port}'));
      final token = await client.pair(nonce);
      // No PIN is set: the create is accepted with any pin value.
      await client.upsertProfile(
        Profile(
          id: '',
          name: 'Maya',
          avatar: 'M',
          allowance: AllowanceMinutes.fromMinutes(allowance)!,
        ),
        '',
      );
      final st = await client.state();
      return (token, st.profiles.single.id, freshServer, freshDb);
    }

    test('addTime accepts any pin value while no PIN is set', () async {
      final (_, id, freshServer, freshDb) = await bootFreshWithProfile();
      try {
        final token = await pairOn(freshServer, freshServer.port);
        for (final anyPin in ['', '0000', '999999']) {
          final (status, _) = await call('POST', '/api/time',
              body: {'profileId': id, 'addSeconds': 60, 'pin': anyPin},
              token: token,
              onPort: freshServer.port);
          expect(status, 200, reason: 'pin "$anyPin" must be accepted');
        }
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });

    test('mutations without a pin field are also accepted while unset',
        () async {
      final (_, id, freshServer, freshDb) = await bootFreshWithProfile();
      try {
        final token = await pairOn(freshServer, freshServer.port);
        final (status, _) = await call('POST', '/api/time',
            body: {'profileId': id, 'addSeconds': 60},
            token: token,
            onPort: freshServer.port);
        expect(status, 200, reason: 'no PIN set -> no pin check at all');
        final (overrideStatus, _) = await call('PUT', '/api/time/$id',
            body: {'remainingSeconds': 300},
            token: token,
            onPort: freshServer.port);
        expect(overrideStatus, 200);
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });

    test('master lock toggles without a pin while unset', () async {
      final (_, _, freshServer, freshDb) = await bootFreshWithProfile();
      try {
        final token = await pairOn(freshServer, freshServer.port);
        final (status, _) = await call('POST', '/api/lock',
            body: {'enabled': true}, token: token, onPort: freshServer.port);
        expect(status, 200);
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });

    test('a 403 is restored the moment a PIN is set', () async {
      final (_, id, freshServer, freshDb) = await bootFreshWithProfile();
      try {
        final token = await pairOn(freshServer, freshServer.port);
        await call('PUT', '/api/pin',
            body: {'pin': '4321'}, token: token, onPort: freshServer.port);
        final (status, _) = await call('POST', '/api/time',
            body: {'profileId': id, 'addSeconds': 60, 'pin': '0000'},
            token: token,
            onPort: freshServer.port);
        expect(status, 403, reason: 'once set, the gate is real again');
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });

    test('EngineCoordinator.setParentPin sets and clears the PIN, '
        'preserving the other settings', () async {
      final (freshServer, freshDb) = await bootFresh();
      try {
        final coord = freshServer.coordinator;
        final token = await pairOn(freshServer, freshServer.port);
        await freshDb.saveSettings(Settings(
          parentPin: '',
          token: token,
          masterLockEnabled: true,
          lockedActiveProfileId: 'p1',
        ));

        await coord.setParentPin('5678');
        var settings = await freshDb.getSettings();
        expect(settings.parentPin, '5678');
        expect(settings.token, token, reason: 'the token is preserved');
        expect(settings.masterLockEnabled, isTrue);
        expect(settings.lockedActiveProfileId, 'p1');

        // Clearing: the TV's "Remove PIN" path (empty = none set).
        await coord.setParentPin('');
        settings = await freshDb.getSettings();
        expect(settings.parentPin, isEmpty);
        expect(settings.token, token);
      } finally {
        await freshServer.stop();
        await freshDb.close();
      }
    });
  });
}
