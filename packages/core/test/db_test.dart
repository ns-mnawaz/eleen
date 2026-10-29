import 'package:drift/native.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:test/test.dart';

void main() {
  late EleenDatabase db;

  setUp(() {
    db = EleenDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('profiles', () {
    test('upsert/read round-trip preserves all fields', () async {
      const p = Profile(
        id: 'kid-1',
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      await db.upsertProfile(p);

      final all = await db.allProfiles();
      expect(all.length, 1);
      expect(all.single.id, 'kid-1');
      expect(all.single.name, 'Maya');
      expect(all.single.avatar, 'fox');
      expect(all.single.allowance, AllowanceMinutes.thirty);
    });

    test('round-trip preserves isParent', () async {
      const parent = Profile(
        id: 'ava',
        name: 'Ava',
        avatar: 'bear',
        allowance: AllowanceMinutes.thirty,
        isParent: true,
      );
      const child = Profile(
        id: 'kid-1',
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );

      await db.upsertProfile(parent);
      await db.upsertProfile(child);

      final all = await db.allProfiles();
      expect(all.length, 2);
      expect(all.firstWhere((p) => p.id == 'ava').isParent, isTrue);
      expect(all.firstWhere((p) => p.id == 'kid-1').isParent, isFalse);
    });

    test('upserting the same id replaces the row', () async {
      await db.upsertProfile(const Profile(
        id: 'kid-1',
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      ));
      await db.upsertProfile(const Profile(
        id: 'kid-1',
        name: 'Maya',
        avatar: 'cat',
        allowance: AllowanceMinutes.sixty,
      ));

      final all = await db.allProfiles();
      expect(all.length, 1);
      expect(all.single.avatar, 'cat');
      expect(all.single.allowance, AllowanceMinutes.sixty);
    });

    test('deleteProfile removes only the matching profile', () async {
      await db.upsertProfile(const Profile(
        id: 'kid-1',
        name: 'Maya',
        avatar: 'fox',
        allowance: AllowanceMinutes.fifteen,
      ));
      await db.upsertProfile(const Profile(
        id: 'kid-2',
        name: 'Leo',
        avatar: 'bear',
        allowance: AllowanceMinutes.fortyFive,
      ));

      await db.deleteProfile('kid-1');

      final all = await db.allProfiles();
      expect(all.length, 1);
      expect(all.single.id, 'kid-2');
    });
  });

  group('sessions', () {
    test('saveSession/sessionFor round-trip persists remaining seconds',
        () async {
      final date = DateTime(2026, 10, 23);
      final s = SessionState(
        profileId: 'kid-1',
        date: date,
        remainingSeconds: 735,
        active: true,
      );

      await db.saveSession(s);

      final loaded = await db.sessionFor(date);
      expect(loaded, isNotNull);
      expect(loaded!.profileId, 'kid-1');
      expect(loaded.remainingSeconds, 735);
      expect(loaded.active, isTrue);
      // Date is stored date-only and comes back normalized to midnight local.
      expect(loaded.date.year, 2026);
      expect(loaded.date.month, 10);
      expect(loaded.date.day, 23);
    });

    test('sessionFor returns null for a day with no saved session',
        () async {
      expect(await db.sessionFor(DateTime(2026, 10, 22)), isNull);
    });

    test('saving a session for the same profile and day overwrites it',
        () async {
      final date = DateTime(2026, 10, 23);
      await db.saveSession(SessionState(
        profileId: 'kid-1',
        date: date,
        remainingSeconds: 900,
        active: true,
      ));
      await db.saveSession(SessionState(
        profileId: 'kid-1',
        date: date,
        remainingSeconds: 300,
        active: false,
      ));

      final loaded = await db.sessionFor(date);
      expect(loaded!.remainingSeconds, 300);
      expect(loaded.active, isFalse);
    });
    test('sessionFor prefers the active session for the day', () async {
      final date = DateTime(2026, 10, 23);
      await db.saveSession(SessionState(
        profileId: 'kid-1',
        date: date,
        remainingSeconds: 900,
        active: false,
      ));
      await db.saveSession(SessionState(
        profileId: 'kid-2',
        date: date,
        remainingSeconds: 400,
        active: true,
      ));

      final loaded = await db.sessionFor(date);
      expect(loaded!.profileId, 'kid-2');
      expect(loaded.remainingSeconds, 400);
    });
  });

  group('settings', () {
    test('getSettings returns defaults when nothing was saved', () async {
      final s = await db.getSettings();
      expect(s.parentPin, '');
      expect(s.token, isNull);
      expect(s.masterLockEnabled, isFalse);
    });

    test('settings round-trip incl. masterLockEnabled', () async {
      await db.saveSettings(const Settings(
        parentPin: '1234',
        token: 'pair-token',
        masterLockEnabled: true,
      ));

      final s = await db.getSettings();
      expect(s.parentPin, '1234');
      expect(s.token, 'pair-token');
      expect(s.masterLockEnabled, isTrue);
    });

    test('saving settings again replaces the single row', () async {
      await db.saveSettings(const Settings(parentPin: '1234'));
      await db.saveSettings(const Settings(parentPin: '9999', token: 't'));

      final s = await db.getSettings();
      expect(s.parentPin, '9999');
      expect(s.token, 't');
      expect(s.masterLockEnabled, isFalse);
    });
  });
}
