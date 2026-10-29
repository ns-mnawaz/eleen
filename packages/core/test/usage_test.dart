// Daily usage records (v1.1 D): per-profile per-day usedSeconds, the events
// log, the v3->v4 migration, the state payload's usage block and the
// shutdown -> powerOn recovery pair.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:test/test.dart';

/// Mutable [Clock] for deterministic coordinator tests.
class FakeClock implements Clock {
  FakeClock(this.date);

  final DateTime date;
  int _ms = 0;

  void advanceMs(int ms) => _ms += ms;

  @override
  int nowMs() => _ms;

  @override
  DateTime today() => date;
}

void main() {
  late EleenDatabase db;

  setUp(() {
    db = EleenDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('usage records (db)', () {
    test('addUsedSeconds accumulates across upserts on the same day',
        () async {
      final date = DateTime(2026, 10, 24);
      await db.addUsedSeconds('kid-1', date, 600);
      await db.addUsedSeconds('kid-1', date, 300);

      expect(await db.usedSecondsFor('kid-1', date), 900);
      // Other profiles and days are untouched.
      expect(await db.usedSecondsFor('kid-2', date), 0);
      expect(await db.usedSecondsFor('kid-1', DateTime(2026, 10, 23)), 0);
    });

    test('a zero delta does not create a row', () async {
      await db.addUsedSeconds('kid-1', DateTime(2026, 10, 24), 0);
      expect(await db.usageHistory('kid-1'), isEmpty);
    });

    test('usageHistory returns the newest days first, capped at 14',
        () async {
      // 20 days of history for kid-1.
      for (var d = 1; d <= 20; d++) {
        await db.addUsedSeconds('kid-1', DateTime(2026, 10, d), d * 60);
      }
      // A second profile's rows never leak in.
      await db.addUsedSeconds('kid-2', DateTime(2026, 10, 24), 42);

      final history = await db.usageHistory('kid-1');
      expect(history.length, 14);
      // Newest first: Oct 20 ... Oct 7.
      expect(history.first.date, DateTime(2026, 10, 20));
      expect(history.first.seconds, 20 * 60);
      expect(history.last.date, DateTime(2026, 10, 7));
    });
  });

  group('usage events (db)', () {
    test('recordEvent round-trips type, detail and date in insert order',
        () async {
      final date = DateTime(2026, 10, 24);
      await db.recordEvent(
          profileId: 'kid-1',
          date: date,
          type: UsageEventType.sessionStart,
          detail: null,
          createdAtMs: 1000);
      await db.recordEvent(
          profileId: 'kid-1',
          date: date,
          type: UsageEventType.limitHit,
          detail: 'remaining=0',
          createdAtMs: 2000);

      final events = await db.eventsFor('kid-1');
      expect(events.length, 2);
      expect(events[0].type, UsageEventType.sessionStart);
      expect(events[0].detail, isNull);
      expect(events[0].date, date);
      expect(events[0].createdAtMs, 1000);
      expect(events[1].type, UsageEventType.limitHit);
      expect(events[1].detail, 'remaining=0');
      expect(events[1].createdAtMs, 2000);
      // Events of other profiles do not leak.
      expect(await db.eventsFor('kid-2'), isEmpty);
    });

    test('createdAt defaults to wall-clock milliseconds when omitted',
        () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      await db.recordEvent(
          profileId: 'kid-1',
          date: DateTime(2026, 10, 24),
          type: UsageEventType.powerOn);
      final after = DateTime.now().millisecondsSinceEpoch;

      final event = (await db.eventsFor('kid-1')).single;
      expect(event.createdAtMs, inInclusiveRange(before, after));
    });
  });

  group('meta (db)', () {
    test('getMetaInt returns null when unset and round-trips', () async {
      expect(await db.getMetaInt('lastTickUptimeMs'), isNull);
      await db.setMetaInt('lastTickUptimeMs', 12345);
      expect(await db.getMetaInt('lastTickUptimeMs'), 12345);
      await db.setMetaInt('lastTickUptimeMs', null);
      expect(await db.getMetaInt('lastTickUptimeMs'), isNull);
    });
  });

  group('migration v3 -> v4', () {
    late Directory tempDir;
    late File dbFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('eleen-migration');
      dbFile = File(p.join(tempDir.path, 'eleen.sqlite3'));
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    /// Opens the file with a RAW sqlite3 connection (no drift — drift would
    /// run onCreate and build the v4 schema before we can simulate v3),
    /// builds the exact v3 schema by hand, seeds data, and closes.
    void seedV3() {
      final raw = sql.sqlite3.open(dbFile.path);
      raw.execute('PRAGMA user_version = 3');
      raw.execute(
          'CREATE TABLE profiles (id TEXT NOT NULL PRIMARY KEY, '
          'name TEXT NOT NULL, avatar TEXT NOT NULL, '
          'allowance_minutes INTEGER NOT NULL, '
          'is_parent INTEGER NOT NULL DEFAULT 0)');
      raw.execute(
          'CREATE TABLE sessions (profile_id TEXT NOT NULL, '
          'date_key INTEGER NOT NULL, remaining_seconds INTEGER NOT NULL, '
          'active INTEGER NOT NULL, PRIMARY KEY (profile_id, date_key))');
      raw.execute(
          'CREATE TABLE app_settings (id INTEGER NOT NULL PRIMARY KEY, '
          "parent_pin TEXT NOT NULL DEFAULT '', token TEXT NULL, "
          'master_lock_enabled INTEGER NOT NULL DEFAULT 0, '
          'locked_active_profile_id TEXT NULL)');
      raw.execute(
          "INSERT INTO profiles VALUES ('kid-1', 'Maya', 'fox', 30, 0)");
      raw.execute(
          "INSERT INTO sessions VALUES ('kid-1', 20261023, 700, 0)");
      raw.execute(
          "INSERT INTO app_settings (id, parent_pin, token, "
          "master_lock_enabled, locked_active_profile_id) VALUES "
          "(1, '1234', 'pair-token', 0, NULL)");
      raw.dispose();
    }

    test('existing data survives and the new tables work', () async {
      seedV3();

      final upgraded = EleenDatabase(NativeDatabase(dbFile));
      // Old data intact.
      final profiles = await upgraded.allProfiles();
      expect(profiles.single.id, 'kid-1');
      expect(profiles.single.name, 'Maya');
      expect(profiles.single.isParent, isFalse);
      final session =
          await upgraded.sessionForProfile('kid-1', DateTime(2026, 10, 23));
      expect(session!.remainingSeconds, 700);
      final settings = await upgraded.getSettings();
      expect(settings.parentPin, '1234');
      expect(settings.token, 'pair-token');

      // The new tables accept writes.
      await upgraded.addUsedSeconds('kid-1', DateTime(2026, 10, 24), 600);
      expect(await upgraded.usedSecondsFor('kid-1', DateTime(2026, 10, 24)),
          600);
      await upgraded.recordEvent(
          profileId: 'kid-1',
          date: DateTime(2026, 10, 24),
          type: UsageEventType.powerOn);
      expect((await upgraded.eventsFor('kid-1')).single.type,
          UsageEventType.powerOn);
      await upgraded.setMetaInt('lastTickUptimeMs', 999);
      expect(await upgraded.getMetaInt('lastTickUptimeMs'), 999);
      await upgraded.close();
    });
  });

  group('EngineCoordinator usage', () {
    final today = DateTime(2026, 10, 24);
    late FakeClock clock;

    setUp(() {
      clock = FakeClock(today);
    });

    EngineCoordinator coordinatorWith(EleenDatabase db) => EngineCoordinator(
          db: db,
          engine: TimeEngine(clock: clock, speedFactor: 1),
        );

    test('state() includes usage with todaySeconds and the 14-day history',
        () async {
      final coord = coordinatorWith(db);
      final kid = await coord.createProfile(
          name: 'Maya', avatar: 'fox', allowance: AllowanceMinutes.fifteen);
      // A profile with no usage still gets an entry (todaySeconds 0).
      final other = await coord.createProfile(
          name: 'Leo', avatar: 'bear', allowance: AllowanceMinutes.thirty);
      // Two days of usage.
      await db.addUsedSeconds(kid.id, DateTime(2026, 10, 23), 1500);
      await db.addUsedSeconds(kid.id, today, 600);

      final st = await coord.state();
      final usage = st.usageByProfile[kid.id];
      expect(usage, isNotNull);
      expect(usage!.todaySeconds, 600);
      expect(usage.history.map((d) => d.date), [today, DateTime(2026, 10, 23)]);
      expect(usage.history.first.seconds, 600);

      expect(st.usageByProfile[other.id]!.todaySeconds, 0);
    });

    test('addTime records an addTime event with the amount', () async {
      final coord = coordinatorWith(db);
      final kid = await coord.createProfile(
          name: 'Maya', avatar: 'fox', allowance: AllowanceMinutes.fifteen);

      await coord.addTime(kid.id, 600);

      final events = await db.eventsFor(kid.id);
      expect(events.single.type, UsageEventType.addTime);
      expect(events.single.detail, '600');
      expect(events.single.date, today);
    });

    test('overrideRemaining records an override event with the new value',
        () async {
      final coord = coordinatorWith(db);
      final kid = await coord.createProfile(
          name: 'Maya', avatar: 'fox', allowance: AllowanceMinutes.fifteen);

      await coord.overrideRemaining(kid.id, 300);

      final events = await db.eventsFor(kid.id);
      expect(events.single.type, UsageEventType.overrideTime);
      expect(events.single.detail, '300');
    });

    test('setMasterLock records masterLockOn and masterLockOff events',
        () async {
      final coord = coordinatorWith(db);
      await coord.createProfile(
          name: 'Maya', avatar: 'fox', allowance: AllowanceMinutes.fifteen);

      await coord.setMasterLock(true);
      await coord.setMasterLock(false);

      // The lock is app-global, so the pair is recorded against the
      // app-global profile id (like shutdown/powerOn).
      final events = await db.eventsFor(EleenDatabase.appGlobalProfileId);
      expect(events.map((e) => e.type),
          [UsageEventType.masterLockOn, UsageEventType.masterLockOff]);
    });

    test('recoverShutdown records nothing on the very first run', () async {
      final coord = coordinatorWith(db);
      await coord.recoverShutdown();
      final kid = await coord.createProfile(
          name: 'Maya', avatar: 'fox', allowance: AllowanceMinutes.fifteen);
      expect(await db.eventsFor(kid.id), isEmpty);
      // Global events (profileId '') are empty too.
      expect(await db.eventsFor(EleenDatabase.appGlobalProfileId), isEmpty);
    });

    test('recoverShutdown records the shutdown->powerOn pair and never '
        'invents used time', () async {
      final coord = coordinatorWith(db);
      final kid = await coord.createProfile(
          name: 'Maya', avatar: 'fox', allowance: AllowanceMinutes.fifteen);

      // Previous run: used 600 s this day, marker at monotonic 100000.
      await db.addUsedSeconds(kid.id, today, 600);
      await db.setMetaInt(EleenDatabase.lastTickUptimeMsKey, 100000);

      // The device was down for 5 "monotonic" seconds (same boot restart).
      clock.advanceMs(105000);
      await coord.recoverShutdown();

      final global = await db.eventsFor(EleenDatabase.appGlobalProfileId);
      expect(global.map((e) => e.type),
          [UsageEventType.shutdown, UsageEventType.powerOn]);
      // Elapsed-while-down is recorded as detail, not as used time.
      expect(global[0].detail, contains('5000'));
      // No phantom time: usedSeconds stays at the last persisted value.
      expect(await db.usedSecondsFor(kid.id, today), 600);
      // A second call in the same process does not duplicate the pair.
      await coord.recoverShutdown();
      expect(
          await db.eventsFor(EleenDatabase.appGlobalProfileId), hasLength(2));
    });

    test('recoverShutdown after a reboot (monotonic clock reset) records '
        'the pair without a down-duration', () async {
      final coord = coordinatorWith(db);
      // Marker from a previous boot with a large monotonic value.
      await db.setMetaInt(EleenDatabase.lastTickUptimeMsKey, 999999999);
      await coord.recoverShutdown();

      final global = await db.eventsFor(EleenDatabase.appGlobalProfileId);
      expect(global.map((e) => e.type),
          [UsageEventType.shutdown, UsageEventType.powerOn]);
      expect(global[0].detail, isNotNull);
    });
  });
}
