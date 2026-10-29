/// Drift-backed persistence for Eleen: profiles, per-day session state and
/// parent settings (single row).
///
/// [AllowanceMinutes] is stored as its `minutes` int (5/15/30/45/60).
/// [SessionState.date] is stored date-only (`yyyymmdd` int), matching the
/// time engine's normalized midnight-local dates.
library eleen_core.db;

import 'package:drift/drift.dart';

import 'models.dart';

part 'db.g.dart';

/// One profile on the TV (child or parent).
///
/// The generated row class is named [ProfileRow] so it cannot be confused
/// with the domain model [Profile].
@DataClassName('ProfileRow')
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get avatar => text()();

  /// The [AllowanceMinutes] allowance, serialized as its minutes int.
  /// Ignored for parent profiles (their sessions are never ticked).
  IntColumn get allowanceMinutes => integer()();

  /// Parent profiles need the parent PIN to select on the TV and never
  /// expire (v3).
  BoolColumn get isParent => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A single day's session state, keyed by profile and date.
class Sessions extends Table {
  TextColumn get profileId => text()();

  /// Date-only key `yyyymmdd`, derived from the engine's normalized dates.
  IntColumn get dateKey => integer()();
  IntColumn get remainingSeconds => integer()();
  BoolColumn get active => boolean()();

  @override
  Set<Column> get primaryKey => {profileId, dateKey};
}

/// Parent-controlled settings. A single row with [AppSettings.id] = 1.
class AppSettings extends Table {
  /// Always 1; the table intentionally holds at most one row.
  IntColumn get id => integer()();
  TextColumn get parentPin => text().withDefault(const Constant(''))();
  TextColumn get token => text().nullable()();
  BoolColumn get masterLockEnabled =>
      boolean().withDefault(const Constant(false))();

  /// The profile whose active session was locked away by the last master
  /// lock (v2). Null when none was active at lock time.
  TextColumn get lockedActiveProfileId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Daily usage per profile (v1.1 D): how many session seconds were used on
/// a given day. Keyed like [Sessions] (profile + date-only key); rows are
/// only written for days something was actually used.
class UsageRecords extends Table {
  TextColumn get profileId => text()();

  /// Date-only key `yyyymmdd`, matching [Sessions.dateKey].
  IntColumn get dateKey => integer()();
  IntColumn get usedSeconds => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {profileId, dateKey};
}

/// Append-only usage event log (v1.1 D): session start/end, limit hits,
/// shutdown/power-on pairs, add-time/override/master-lock operations.
/// Storage-only in v1.1 (for future reports); not exposed on the wire.
@DataClassName('UsageEventRow')
class UsageEvents extends Table {
  /// Auto-incrementing log sequence (insert order).
  IntColumn get id => integer().autoIncrement()();

  /// [EleenDatabase.appGlobalProfileId] for app-global events (the
  /// shutdown/powerOn pair, which belong to no single profile).
  TextColumn get profileId => text()();

  /// Date-only key `yyyymmdd` of the day the event belongs to.
  IntColumn get dateKey => integer()();
  TextColumn get type => text()();

  /// Free-form detail, e.g. the added seconds of an addTime event.
  TextColumn get detail => text().nullable()();

  /// Wall-clock epoch milliseconds when the event was recorded.
  IntColumn get createdAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tiny key-value store for single scalar markers (v1.1 D): the tick loop
/// persists the monotonic [EleenDatabase.lastTickUptimeMsKey] here so a
/// relaunch can record the shutdown -> powerOn pair.
@DataClassName('MetaRow')
class Meta extends Table {
  TextColumn get key => text()();
  IntColumn get intValue => integer().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Profiles, Sessions, AppSettings, UsageRecords, UsageEvents, Meta])
class EleenDatabase extends _$EleenDatabase {
  EleenDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // v2: the locked-away active profile id on AppSettings.
          if (from < 2) {
            await m.addColumn(appSettings, appSettings.lockedActiveProfileId);
          }
          // v3: parent/child profile types; every existing profile is a
          // child (the column default).
          if (from < 3) {
            await m.addColumn(profiles, profiles.isParent);
          }
          // v4: daily usage records, the event log and the meta markers.
          if (from < 4) {
            await m.createTable(usageRecords);
            await m.createTable(usageEvents);
            await m.createTable(meta);
          }
        },
      );

  // --- Profiles ---

  Future<List<Profile>> allProfiles() async {
    final rows = await select(profiles).get();
    return [
      for (final row in rows)
        Profile(
          id: row.id,
          name: row.name,
          avatar: row.avatar,
          allowance:
              AllowanceMinutes.fromMinutes(row.allowanceMinutes) ??
              AllowanceMinutes.thirty,
          isParent: row.isParent,
        ),
    ];
  }

  Future<void> upsertProfile(Profile p) =>
      into(profiles).insertOnConflictUpdate(
        ProfilesCompanion.insert(
          id: p.id,
          name: p.name,
          avatar: p.avatar,
          allowanceMinutes: p.allowance.minutes,
          isParent: Value(p.isParent),
        ),
      );

  Future<void> deleteProfile(String id) =>
      (delete(profiles)..where((t) => t.id.equals(id))).go();

  // --- Sessions ---

  Future<SessionState?> sessionFor(DateTime date) async {
    final key = _dateKey(date);
    final query = select(sessions)..where((t) => t.dateKey.equals(key));
    final rows = await query.get();
    if (rows.isEmpty) return null;
    // One session is "the" session for the day (see TvState.activeSession):
    // prefer the active one, fall back to the first row deterministically.
    final row =
        rows.firstWhere((r) => r.active, orElse: () => rows.first);
    return SessionState(
      profileId: row.profileId,
      date: _dateFromKey(row.dateKey),
      remainingSeconds: row.remainingSeconds,
      active: row.active,
    );
  }

  Future<void> saveSession(SessionState s) =>
      into(sessions).insertOnConflictUpdate(
        SessionsCompanion.insert(
          profileId: s.profileId,
          dateKey: _dateKey(s.date),
          remainingSeconds: s.remainingSeconds,
          active: s.active,
        ),
      );

  /// The session of one specific profile on [date], or null.
  ///
  /// Unlike [sessionFor] (which returns "the" session for a day regardless of
  /// owner), this is scoped to a single profile, so orphaned sessions of
  /// deleted profiles are never returned (see the deleteProfile ruling).
  Future<SessionState?> sessionForProfile(String profileId, DateTime date) async {
    final key = _dateKey(date);
    final row = await (select(sessions)
          ..where((t) => t.profileId.equals(profileId) & t.dateKey.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return SessionState(
      profileId: row.profileId,
      date: _dateFromKey(row.dateKey),
      remainingSeconds: row.remainingSeconds,
      active: row.active,
    );
  }

  // --- Settings ---

  Future<Settings> getSettings() async {
    final row =
        await (select(appSettings)..where((t) => t.id.equals(1)))
            .getSingleOrNull();
    if (row == null) return const Settings(parentPin: '');
    return Settings(
      parentPin: row.parentPin,
      token: row.token,
      masterLockEnabled: row.masterLockEnabled,
      lockedActiveProfileId: row.lockedActiveProfileId,
    );
  }

  Future<void> saveSettings(Settings s) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          id: const Value(1),
          parentPin: Value(s.parentPin),
          token: Value(s.token),
          masterLockEnabled: Value(s.masterLockEnabled),
          lockedActiveProfileId: Value(s.lockedActiveProfileId),
        ),
      );

  // --- Usage records (v1.1 D) ---

  /// Adds [seconds] of used time to [profileId]'s [date] row. A single
  /// upsert (the tick loop calls this every second — keep it cheap); a
  /// zero delta writes nothing.
  Future<void> addUsedSeconds(
      String profileId, DateTime date, int seconds) async {
    if (seconds == 0) return;
    await customStatement(
      'INSERT INTO usage_records (profile_id, date_key, used_seconds) '
      'VALUES (?, ?, ?) '
      'ON CONFLICT (profile_id, date_key) DO UPDATE '
      'SET used_seconds = used_seconds + excluded.used_seconds',
      [profileId, _dateKey(date), seconds],
    );
  }

  /// The seconds [profileId] used on [date] (0 when nothing was recorded).
  Future<int> usedSecondsFor(String profileId, DateTime date) async {
    final row = await (select(usageRecords)
          ..where((t) =>
              t.profileId.equals(profileId) & t.dateKey.equals(_dateKey(date))))
        .getSingleOrNull();
    return row?.usedSeconds ?? 0;
  }

  /// The last [maxDays] days with recorded usage for [profileId], newest
  /// first. Days without usage are absent.
  Future<List<DayUsage>> usageHistory(String profileId,
      {int maxDays = 14}) async {
    final rows = await (select(usageRecords)
          ..where((t) => t.profileId.equals(profileId))
          ..orderBy([(u) => OrderingTerm.desc(u.dateKey)])
          ..limit(maxDays))
        .get();
    return [
      for (final row in rows)
        DayUsage(date: _dateFromKey(row.dateKey), seconds: row.usedSeconds),
    ];
  }

  // --- Usage events (v1.1 D) ---

  /// Appends one usage event. [createdAtMs] defaults to the wall clock.
  Future<void> recordEvent({
    required String profileId,
    required DateTime date,
    required UsageEventType type,
    String? detail,
    int? createdAtMs,
  }) async {
    await into(usageEvents).insert(
      UsageEventsCompanion.insert(
        profileId: profileId,
        dateKey: _dateKey(date),
        type: type.name,
        detail: Value(detail),
        createdAtMs: createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// The recorded events of [profileId] in insert order.
  Future<List<UsageEvent>> eventsFor(String profileId) async {
    final rows = await (select(usageEvents)
          ..where((t) => t.profileId.equals(profileId))
          ..orderBy([(u) => OrderingTerm.asc(u.id)]))
        .get();
    return [
      for (final row in rows)
        UsageEvent(
          id: row.id,
          profileId: row.profileId,
          date: _dateFromKey(row.dateKey),
          type: UsageEventType.values.byName(row.type),
          detail: row.detail,
          createdAtMs: row.createdAtMs,
        ),
    ];
  }

  // --- Meta markers ---

  /// The integer [key] marker, or null when unset.
  Future<int?> getMetaInt(String key) async {
    final row = await (select(meta)..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.intValue;
  }

  /// Writes (or clears with null) the integer [key] marker.
  Future<void> setMetaInt(String key, int? value) async {
    await into(meta).insertOnConflictUpdate(
      MetaCompanion.insert(key: key, intValue: Value(value)),
    );
  }

  // --- Date serialization (date-only, engine-normalized) ---

  static int _dateKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  static DateTime _dateFromKey(int key) =>
      DateTime(key ~/ 10000, key ~/ 100 % 100, key % 100);

  /// The profileId recorded on app-global usage events (shutdown/powerOn):
  /// they belong to no single profile.
  static const String appGlobalProfileId = '';

  /// The meta key holding the monotonic uptime (ms) of the last tick —
  /// persisted every tick so a relaunch can record the shutdown ->
  /// powerOn pair without inventing time past the last persisted marker.
  static const String lastTickUptimeMsKey = 'lastTickUptimeMs';
}
