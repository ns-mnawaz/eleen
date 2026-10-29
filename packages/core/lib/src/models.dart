/// Domain models for Eleen.
library eleen_core.models;

/// The daily screen-time allowance a child profile may use.
enum AllowanceMinutes {
  five(5),
  fifteen(15),
  thirty(30),
  fortyFive(45),
  sixty(60);

  const AllowanceMinutes(this._minutes);

  final int _minutes;

  /// The allowance in minutes.
  int get minutes => _minutes;

  /// Returns the [AllowanceMinutes] for [m], or null if [m] is not a valid
  /// allowance (only 5, 15, 30, 45 and 60 are allowed).
  static AllowanceMinutes? fromMinutes(int m) {
    for (final v in AllowanceMinutes.values) {
      if (v._minutes == m) return v;
    }
    return null;
  }
}

/// A profile on the TV — a child with a screen-time allowance, or a parent
/// (an unrestricted session that never expires into the lock overlay).
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.allowance,
    this.isParent = false,
  });

  final String id;
  final String name;
  final String avatar;
  final AllowanceMinutes allowance;

  /// Whether this is a parent profile. Parent sessions are never ticked or
  /// locked by the time engine (the allowance does not apply); selecting one
  /// on the TV requires the parent PIN.
  final bool isParent;
}

/// A single day's session state for a profile.
class SessionState {
  const SessionState({
    required this.profileId,
    required this.date,
    required this.remainingSeconds,
    required this.active,
  });

  final String profileId;
  final DateTime date;
  final int remainingSeconds;
  final bool active;
}

/// Snapshot of the TV-side state.
class TvState {
  const TvState({
    required this.profiles,
    required this.activeSession,
    this.masterLockEnabled = false,
    this.parentPinSet = false,
    required this.remainingByProfile,
    this.usageByProfile = const {},
    this.overlayPermissionGranted = true,
  });

  final List<Profile> profiles;
  final SessionState? activeSession;
  final bool masterLockEnabled;

  /// Whether the TV currently holds the SYSTEM_ALERT_WINDOW ("Display over
  /// other apps") permission — without it, the TV can't lock other apps.
  /// Reported by the TV app (a live platform check, not stored state);
  /// defaults to true and older servers omit it, so clients must tolerate
  /// its absence.
  final bool overlayPermissionGranted;

  /// Whether a parent PIN has been provisioned on the TV. A fresh install
  /// reports false, so the pairing phone knows to walk the parent through
  /// PIN setup right after pairing.
  final bool parentPinSet;

  final Map<String, int> remainingByProfile;

  /// Per-profile daily usage (v1.1 D). Empty when the server predates the
  /// usage records feature — clients must tolerate its absence.
  final Map<String, ProfileUsage> usageByProfile;
}

/// One day's usage: how many session seconds a profile used on [date]
/// (date-only, normalized to midnight local).
class DayUsage {
  const DayUsage({required this.date, required this.seconds});

  final DateTime date;
  final int seconds;

  /// The wire format for a date-only value: `2026-10-24`.
  static String wire(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// A profile's daily usage: today's total plus recent history (newest
/// first; the server caps it at the last 14 days).
class ProfileUsage {
  const ProfileUsage({
    required this.todaySeconds,
    required this.history,
  });

  final int todaySeconds;
  final List<DayUsage> history;
}

/// The lifecycle/mutation events recorded in the usage log (v1.1 D).
///
/// Stored by name in the `usage_events` table; the wire never carries them
/// in v1.1 (storage-only, for future reports).
enum UsageEventType {
  sessionStart,
  sessionEnd,
  limitHit,
  shutdown,
  powerOn,
  addTime,
  overrideTime,
  masterLockOn,
  masterLockOff,
}

/// One recorded usage event (an append-only log row).
class UsageEvent {
  const UsageEvent({
    required this.id,
    required this.profileId,
    required this.date,
    required this.type,
    this.detail,
    required this.createdAtMs,
  });

  final int id;
  final String profileId;
  final DateTime date;
  final UsageEventType type;

  /// Free-form detail, e.g. the added seconds of an addTime event.
  final String? detail;

  /// Wall-clock epoch milliseconds when the event was recorded.
  final int createdAtMs;
}

/// Parent-controlled settings.
class Settings {
  const Settings({
    required this.parentPin,
    this.token,
    this.masterLockEnabled = false,
    this.lockedActiveProfileId,
  });

  final String parentPin;
  final String? token;
  final bool masterLockEnabled;

  /// The profile whose active session was put away by the last master-lock
  /// activation. Unlocking reactivates ONLY this profile's session (the
  /// single-active invariant); null when no session was active at lock
  /// time, in which case unlocking restores none.
  final String? lockedActiveProfileId;
}
