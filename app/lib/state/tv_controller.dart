// TV-side application state: a [ChangeNotifier] owning the database, the
// time engine (via the [EngineCoordinator]) and the LAN [EleenServer].
//
// The TV instance is the source of truth; the phone app syncs with it over
// the server this controller exposes.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:eleen_core/eleen_core.dart';

/// Owns [EleenDatabase] + [TimeEngine] (through [EngineCoordinator]) and
/// [EleenServer], and exposes the pieces the TV UI needs:
//
/// - [profiles]: the current child profiles.
/// - [selectProfile]: creates or resumes today's session for a profile.
/// - [stateStream]: every [TvState] snapshot as it changes.
class TvController extends ChangeNotifier {
  TvController({
    required EleenDatabase db,
    Clock? clock,
    int? speedFactor,
  })  : db = db,
        coordinator = EngineCoordinator(
          db: db,
          engine: TimeEngine(
            clock: clock ?? SystemClock(),
            speedFactor: speedFactor ?? defaultSpeedFactor,
          ),
        ) {
    _lastTickMs = coordinator.engine.clock.nowMs();
    _server = EleenServer(coordinator: coordinator);
  }

  /// The database this controller owns (closed on [dispose]).
  final EleenDatabase db;

  /// Domain operations over [db] and the time engine.
  final EngineCoordinator coordinator;

  late final EleenServer _server;
  bool _serverRunning = false;

  /// Wall-time of the last [tick], so each tick consumes only the time that
  /// actually elapsed since the previous one.
  int _lastTickMs = 0;
  Timer? _ticker;
  bool _disposed = false;

  final StreamController<String> _toasts = StreamController<String>.broadcast();

  final StreamController<TvState> _stateController =
      StreamController<TvState>.broadcast();

  TvState? _state;
  List<Profile> _profiles = const [];

  /// The most recent [TvState] snapshot, or null before the first
  /// [refresh].
  TvState? get state => _state;

  /// The current child profiles.
  List<Profile> get profiles => List.unmodifiable(_profiles);

  /// Broadcast stream of every [TvState] snapshot as it changes.
  Stream<TvState> get stateStream => _stateController.stream;

  /// Broadcast stream of reminder-toast messages, emitted when the active
  /// session crosses a reminder threshold (15/10/5 minutes left) for the
  /// first time; the coordinator's fired set suppresses repeats and
  /// re-arms thresholds when time is added.
  Stream<String> get toasts => _toasts.stream;

  /// The user-facing reminder message for a crossed [thresholdSec], e.g.
  /// 600 -> '10 minutes left'.
  static String reminderMessage(int thresholdSec) =>
      '${thresholdSec ~/ 60} minutes left';

  /// The port [startServer] binds when none is passed. Shared with the
  /// pairing screen so the QR payload never hardcodes a second copy.
  static const int defaultServerPort = 8477;

  /// The port the LAN server actually bound, or null before [startServer]
  /// succeeds (port 0 binds pick an ephemeral port, so the pairing screen
  /// must read this rather than assume the default).
  int? get serverPort => _serverRunning ? _server.port : null;

  /// Registers a single-use pairing nonce with the LAN server: the pairing
  /// screen calls this for every nonce it encodes into a QR payload, and
  /// `POST /api/pair` consumes each nonce once.
  void registerPairingNonce(String nonce) => _server.registerNonce(nonce);

  /// Publishes the latest SYSTEM_ALERT_WINDOW probe result to the LAN
  /// server, so paired phones can warn when the TV cannot lock other apps
  /// (TvHome's permission probe calls this after every check).
  void setOverlayPermissionGranted(bool granted) =>
      coordinator.overlayPermissionGranted = granted;

  /// Session-seconds consumed per wall second. Fast tests / E2E set
  /// `--dart-define=ELEN_FAST=1` to get 60 (a 15-minute allowance expires in
  /// ~15 wall seconds).
  static int get defaultSpeedFactor {
    const fast = String.fromEnvironment('ELEN_FAST');
    return fast == '1' ? 60 : 1;
  }

  /// Whether the lock overlay must be up for [st]: master lock, or an active
  /// session played down to zero. A parent profile's session is never locked
  /// by expiry (it is never ticked either); the master lock covers parents
  /// like everyone else. The TV home mounts the lock in its own Stack; the
  /// background platform overlay mirrors it over other apps.
  static bool isLocked(TvState? st) {
    final session = st?.activeSession;
    if (st?.masterLockEnabled ?? false) return true;
    if (session == null || !session.active || session.remainingSeconds > 0) {
      return false;
    }
    final activeProfile =
        st!.profiles.where((p) => p.id == session.profileId).firstOrNull;
    return activeProfile?.isParent != true;
  }

  /// Production controller with a file-backed database in the app documents
  /// directory.
  static Future<TvController> forDevice() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = EleenDatabase(LazyDatabase(() async {
      return NativeDatabase(File(p.join(dir.path, 'eleen.sqlite3')));
    }));
    return TvController(db: db);
  }

  /// Reloads profiles and the state snapshot from the database, notifying
  /// listeners and [stateStream].
  Future<void> refresh() async {
    final st = await coordinator.state();
    _state = st;
    _profiles = st.profiles;
    _stateController.add(st);
    notifyListeners();
  }

  /// Creates today's session for the profile [id] (at the full allowance) or
  /// resumes its existing one, preserving the remaining time.
  ///
  /// Enforces the single-active-session invariant ("pick at session start"):
  /// any other active session for today is deactivated (remaining time
  /// preserved, so that child can resume later) with a sessionEnd usage
  /// event. The master lock therefore never has to arbitrate between active
  /// users.
  ///
  /// Throws [ArgumentError] for an unknown profile id.
  Future<void> selectProfile(String id) async {
    final profile = _profiles.where((p) => p.id == id).firstOrNull;
    if (profile == null) {
      throw ArgumentError.value(id, 'id', 'unknown profile');
    }
    final today = coordinator.engine.clock.today();
    await _deactivateOtherActiveSessions(id, today);
    // Only the time from here on belongs to the new session: reset the tick
    // baseline so idle wall-time before selection is not consumed.
    _lastTickMs = coordinator.engine.clock.nowMs();
    final existing = await db.sessionForProfile(id, today);
    final session = existing == null
        ? SessionState(
            profileId: id,
            date: today,
            remainingSeconds: profile.allowance.minutes * 60,
            active: true,
          )
        : SessionState(
            profileId: id,
            date: existing.date,
            remainingSeconds: existing.remainingSeconds,
            active: true,
          );
    await db.saveSession(session);
    await coordinator.recordUsageEvent(id, UsageEventType.sessionStart);
    await refresh();
  }

  /// Ends the currently active session selection (remaining time preserved),
  /// so the profile picker shows again. Used by "Switch profile" on the TV.
  Future<void> endActiveSession() async {
    final active = state?.activeSession;
    if (active == null) return;
    final today = coordinator.engine.clock.today();
    await db.saveSession(SessionState(
      profileId: active.profileId,
      date: today,
      remainingSeconds: active.remainingSeconds,
      active: false,
    ));
    await coordinator.recordUsageEvent(
        active.profileId, UsageEventType.sessionEnd);
    await refresh();
  }

  /// Deactivates every active session for [today] except [keepProfileId]'s.
  ///
  /// This is the single-active-session invariant: exactly one child plays at
  /// a time. Remaining times are preserved, so a deactivated child can
  /// resume their session later; each deactivation records a sessionEnd
  /// usage event.
  Future<void> _deactivateOtherActiveSessions(
    String keepProfileId,
    DateTime today,
  ) async {
    for (final profile in _profiles) {
      if (profile.id == keepProfileId) continue;
      final session = await db.sessionForProfile(profile.id, today);
      if (session == null || !session.active) continue;
      await db.saveSession(SessionState(
        profileId: session.profileId,
        date: today,
        remainingSeconds: session.remainingSeconds,
        active: false,
      ));
      await coordinator.recordUsageEvent(
          session.profileId, UsageEventType.sessionEnd);
    }
  }

  /// Starts (or restarts) the tick loop: a 1-second [Timer.periodic] driving
  /// [tick]. Owned by the TV home (which shows the live remaining time while
  /// a child session is enforced); [interval] is injectable so tests can
  /// drive [tick] by hand instead of waiting on real time.
  void startTicker({Duration interval = const Duration(seconds: 1)}) {
    _ticker?.cancel();
    _ticker = Timer.periodic(interval, (_) => unawaited(tick()));
  }

  /// Stops the tick loop started by [startTicker].
  void stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Records the shutdown -> powerOn usage-event pair for the PREVIOUS run
  /// of the app (v1.1 D), closing its usage out at the last persisted tick
  /// marker — never inventing time past it. A no-op on the very first run
  /// and at most once per controller. The production bootstrap (TvHome)
  /// calls this right after creating the controller; tests call it
  /// explicitly.
  Future<void> recoverShutdown() => coordinator.recoverShutdown();

  /// One tick of the countdown loop: consumes the wall time elapsed since
  /// the previous tick from the active session's remaining time, persists
  /// the result, and emits a toast when a reminder threshold is crossed for
  /// the first time.
  ///
  /// Every tick also (a) books the consumed session seconds into the daily
  /// usage records (v1.1 D) and (b) persists the monotonic tick marker
  /// ([EleenDatabase.lastTickUptimeMsKey]) so a relaunch can close the
  /// previous run out at exactly this point.
  ///
  /// Ticks are always at least one wall second apart (the engine truncates
  /// sub-second deltas), and each wall second consumes
  /// [TimeEngine.speedFactor] session seconds — 60 in E2E mode.
  Future<void> tick() async {
    // A tick already in flight must not touch the database after dispose
    // closed it.
    if (_disposed) return;
    final nowMs = coordinator.engine.clock.nowMs();
    final deltaMs = nowMs - _lastTickMs;
    _lastTickMs = nowMs;
    if (deltaMs <= 0) return;

    // The shutdown-recovery marker: the last persisted point of the
    // previous run. Nothing is ever booked past it (no phantom time).
    await coordinator.db
        .setMetaInt(EleenDatabase.lastTickUptimeMsKey, nowMs);

    final st = state;
    final session = st?.activeSession;
    if (session == null || !session.active) return;
    final profile =
        st!.profiles.where((p) => p.id == session.profileId).firstOrNull;
    if (profile == null) return;

    // Session seconds this tick consumed (engine convention).
    final consumed = coordinator.engine.consumedSeconds(deltaMs);

    // A parent session never burns time: no ticking, no thresholds, no
    // expiry (the allowance does not apply to parents) — but its usage is
    // still recorded (parents are profiles too).
    if (profile.isParent) {
      await coordinator.db
          .addUsedSeconds(profile.id, session.date, consumed);
      return;
    }

    final advanced =
        coordinator.engine.advance(session, deltaMs, profile.allowance);
    await coordinator.db.saveSession(advanced);
    await refresh();

    // Daily rollover: the engine refilled the allowance and discarded the
    // elapsed wall time, so nothing is booked this tick — the previous
    // day's usedSeconds row already holds the recorded total.
    if (advanced.date != session.date) {
      coordinator.rearmThresholds(session.profileId, advanced.remainingSeconds);
      return;
    }

    // Usage accrual: capped at what the session actually had left, so a
    // tick spanning expiry never books time that was never played.
    final used =
        consumed > session.remainingSeconds ? session.remainingSeconds : consumed;
    await coordinator.db
        .addUsedSeconds(profile.id, session.date, used);

    // A crossing to zero (never a repeat while the session sits at 0)
    // records the limitHit event.
    if (advanced.remainingSeconds == 0 && session.remainingSeconds > 0) {
      await coordinator.recordUsageEvent(
          profile.id, UsageEventType.limitHit);
    }

    final threshold = coordinator.engine.thresholdToFire(
      session.remainingSeconds,
      advanced.remainingSeconds,
      profile.allowance.minutes * 60,
    );
    if (threshold == null) return;
    // The engine is pure: it reports every crossing. Single-fire enforcement
    // is the coordinator's fired set (re-armed by addTime/overrideRemaining).
    if (coordinator.firedThresholds(session.profileId).contains(threshold)) {
      return;
    }
    coordinator.markThresholdFired(session.profileId, threshold);
    _toasts.add(reminderMessage(threshold));
  }

  /// Starts the LAN server on [address]:[port]. A no-op when already
  /// running. Skipped by tests, which exercise [coordinator] directly.
  Future<void> startServer({
    InternetAddress? address,
    int port = defaultServerPort,
  }) async {
    if (_serverRunning) return;
    try {
      await _server.start(
          address: address ?? InternetAddress.anyIPv4, port: port);
      _serverRunning = true;
    } catch (error) {
      // Surface bind failures (port taken, no network) without crashing the
      // TV UI; the phone app just won't be able to pair.
      debugPrint('Eleen: LAN server failed to start: $error');
    }
  }

  Future<void> stopServer() async {
    await _server.stop();
    _serverRunning = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_toasts.close());
    _stateController.close();
    unawaited(_server.stop());
    unawaited(db.close());
    super.dispose();
  }
}
