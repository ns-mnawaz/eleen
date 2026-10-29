/// Pure time logic for Eleen sessions: elapsed-time accounting, daily reset,
/// reminder-threshold detection, last-minute detection and the master lock.
///
/// The engine holds no per-session mutable state: single-fire enforcement of
/// reminder thresholds is the caller's job (a fired set per session, re-armed
/// by clearing entries below the new remaining time when time is added).
library eleen_core.time_engine;

import 'models.dart';

/// Monotonic time source used by [TimeEngine] instead of the wall clock, so
/// session timing never jumps when the system clock changes.
abstract class Clock {
  /// Monotonic milliseconds, e.g. from a [Stopwatch].
  int nowMs();

  /// The current calendar date, used for the daily allowance reset.
  ///
  /// Defaults to deriving the date from [nowMs]; implementations backed by a
  /// monotonic [Stopwatch] (see [SystemClock]) must override this, since
  /// stopwatch milliseconds are not epoch milliseconds.
  DateTime today() => DateTime.fromMillisecondsSinceEpoch(nowMs());
}

/// Production [Clock] backed by a [Stopwatch] (monotonic) plus the wall-clock
/// moment it was started, which together answer both [nowMs] and [today].
class SystemClock implements Clock {
  final Stopwatch _stopwatch = Stopwatch()..start();
  final DateTime _startTime = DateTime.now();

  @override
  int nowMs() => _stopwatch.elapsedMilliseconds;

  @override
  DateTime today() => _startTime.add(_stopwatch.elapsed);
}

/// Pure reducer over [SessionState].
///
/// With [speedFactor] = 1 every engine unit is a real second. With
/// [speedFactor] = 60 (E2E mode) each wall second consumes 60 remaining
/// seconds, so a 15-minute allowance expires in ~15 wall seconds.
class TimeEngine {
  TimeEngine({required Clock clock, int speedFactor = 1})
      : clock = clock,
        speedFactor = speedFactor,
        assert(speedFactor > 0, 'speedFactor must be positive');

  final Clock clock;
  final int speedFactor;

  /// Session seconds consumed by [deltaMs] of wall time — the same math
  /// [advance] applies to the remaining time (callers book the same amount
  /// into the usage records, capped at what was actually left).
  int consumedSeconds(int deltaMs) => deltaMs * speedFactor ~/ 1000;

  /// Reminder thresholds in minutes, highest first.
  static const List<int> _thresholdMinutes = [15, 10, 5];

  /// Advances [s] by [deltaMs] of wall time.
  ///
  /// Consumes `deltaMs * speedFactor` milliseconds of the session's remaining
  /// time, flooring at 0. When the session's [SessionState.date] is not today
  /// (daily reset) the remaining time is refilled to the full [allowance]
  /// instead and the date rolls forward.
  SessionState advance(
    SessionState s,
    int deltaMs,
    AllowanceMinutes allowance,
  ) {
    final refreshed = _rollDateIfNeeded(s, allowance);
    if (!identical(refreshed, s)) return refreshed;

    final consumedSeconds = deltaMs * speedFactor ~/ 1000;
    final remaining = s.remainingSeconds - consumedSeconds;
    return SessionState(
      profileId: s.profileId,
      date: s.date,
      remainingSeconds: remaining < 0 ? 0 : remaining,
      active: s.active,
    );
  }

  /// Returns the reminder threshold (in remaining seconds: 900 / 600 / 300,
  /// i.e. 15 / 10 / 5 minutes of session time) that was crossed between
  /// [remainingSecBefore] and [remainingSecAfter], or null if none was.
  ///
  /// A threshold fires only when it is strictly below [sessionStartSec] (a
  /// session that started with 15 minutes never fires the 15-minute toast)
  /// and only on an actual crossing: `before > threshold >= after`. If a
  /// single tick spans several thresholds, the highest crossed one wins.
  ///
  /// The engine is pure: crossing the same threshold twice (after time was
  /// added and played down again) reports it again. The caller suppresses
  /// repeats via the per-session fired set, and re-arms thresholds by
  /// clearing fired entries below the new remaining time.
  int? thresholdToFire(
    int remainingSecBefore,
    int remainingSecAfter,
    int sessionStartSec,
  ) {
    for (final minutes in _thresholdMinutes) {
      final thresholdSec = minutes * 60;
      if (thresholdSec >= sessionStartSec) continue;
      if (remainingSecBefore > thresholdSec &&
          remainingSecAfter <= thresholdSec) {
        return thresholdSec;
      }
    }
    return null;
  }

  /// Whether the countdown has entered its final window: the last
  /// session-minute — more than zero and at most 60 remaining seconds,
  /// regardless of [speedFactor] (remaining seconds are session units; at
  /// speedFactor 60 that is one wall second before expiry).
  bool inLastMinute(int remainingSec) =>
      remainingSec > 0 && remainingSec <= 60;

  /// Applies the parent master lock.
  ///
  /// Locking preserves [SessionState.remainingSeconds] untouched and marks
  /// the session inactive. Unlocking restores the session (active again,
  /// remaining time as preserved), refilling the full allowance if the day
  /// rolled over while locked.
  SessionState applyMasterLock(
    SessionState s, {
    required bool locked,
    required AllowanceMinutes allowance,
  }) {
    if (locked) {
      return SessionState(
        profileId: s.profileId,
        date: s.date,
        remainingSeconds: s.remainingSeconds,
        active: false,
      );
    }
    final restored = _rollDateIfNeeded(s, allowance);
    return SessionState(
      profileId: restored.profileId,
      date: restored.date,
      remainingSeconds: restored.remainingSeconds,
      active: true,
    );
  }

  /// Returns a copy of [s] with the full allowance if [s] is from a previous
  /// day, otherwise returns [s] itself.
  SessionState _rollDateIfNeeded(SessionState s, AllowanceMinutes allowance) {
    final today = _dateOnly(clock.today());
    if (_sameDay(s.date, today)) return s;
    return SessionState(
      profileId: s.profileId,
      date: today,
      remainingSeconds: allowance.minutes * 60,
      active: s.active,
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
