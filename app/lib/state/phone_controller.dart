// Phone-side application state: a [ChangeNotifier] that polls the TV over
// the LAN and hands the latest [TvState] to the profiles dashboard.
//
// The TV is the source of truth; this controller only mirrors it. Between
// polls a 1-second ticker decrements the active session's remaining time so
// the rows count down live instead of jumping every 5 seconds.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:eleen_core/eleen_core.dart';

/// The TV operations the phone UI needs.
///
/// [EleenClient] already exposes exactly these signatures, but the
/// indirection lets widget tests inject a fake instead of opening sockets.
abstract interface class EleenOps {
  Future<TvState> state();

  Future<void> addTime(String profileId, int addSeconds, String pin);

  Future<void> overrideTime(
    String profileId,
    int remainingSeconds,
    String pin,
  );

  Future<void> setMasterLock(bool enabled, String pin);

  Future<void> upsertProfile(Profile profile, String pin);
}

/// [EleenOps] over the real [EleenClient].
class EleenClientOps implements EleenOps {
  EleenClientOps(this.client);

  final EleenClient client;

  @override
  Future<TvState> state() => client.state();

  @override
  Future<void> addTime(String profileId, int addSeconds, String pin) =>
      client.addTime(profileId, addSeconds, pin);

  @override
  Future<void> overrideTime(
          String profileId, int remainingSeconds, String pin) =>
      client.overrideTime(profileId, remainingSeconds, pin);

  @override
  Future<void> setMasterLock(bool enabled, String pin) =>
      client.setMasterLock(enabled, pin);

  @override
  Future<void> upsertProfile(Profile profile, String pin) =>
      client.upsertProfile(profile, pin);
}

/// Mirrors the TV state for the phone UI.
///
/// - [state]: the most recent snapshot (null before the first successful
///   poll; retained through failures so rows keep rendering).
/// - [offline]: true when the latest poll could not reach the TV at all.
/// - [error]: the user-facing message for a non-offline failure.
/// - [remainingFor]: live per-profile remaining seconds (counted down
///   between polls for the active session).
///
/// The parent PIN is never stored here — every PIN-gated call forwards it
/// to the TV, which is the only verifier (403 on a wrong PIN).
class PhoneController extends ChangeNotifier {
  PhoneController({
    required EleenOps client,
    this.pollInterval = const Duration(seconds: 5),
  }) : _ops = client {
    _poll = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    unawaited(refresh());
  }

  final EleenOps _ops;

  /// How often [state] is re-fetched from the TV.
  final Duration pollInterval;

  TvState? _state;
  bool _offline = false;
  String? _error;
  Timer? _poll;
  Timer? _ticker;
  bool _fetching = false;
  bool _disposed = false;

  /// The most recent [TvState], or null before the first successful poll.
  ///
  /// Note: the `remainingByProfile` of this snapshot is advanced by the
  /// live ticker for the active session, so it is newer than the last poll.
  TvState? get state => _state;

  /// Whether the TV was unreachable on the latest poll.
  bool get offline => _offline;

  /// The user-facing message for the latest non-offline error, if any.
  String? get error => _error;

  /// Live remaining session seconds for [profileId], from the latest poll
  /// minus the time the active session has burned since. 0 when unknown.
  int remainingFor(String profileId) =>
      _state?.remainingByProfile[profileId] ?? 0;

  /// Re-fetches the TV state now. A no-op while a fetch is already in
  /// flight; a fetch that lands after [dispose] is dropped silently.
  Future<void> refresh() async {
    if (_fetching || _disposed) return;
    _fetching = true;
    try {
      final st = await _ops.state();
      if (_disposed) return;
      _state = st;
      _offline = false;
      _error = null;
    } on Object catch (e) {
      if (_disposed) return;
      if (_isOffline(e)) {
        _offline = true;
        _error = null;
      } else {
        // The TV answered but refused (bad token, server error): keep the
        // last good state and surface the message.
        _offline = false;
        _error = e.toString();
      }
    } finally {
      _fetching = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// PIN-gated: adds [addSeconds] to [profileId]'s session on the TV.
  Future<void> addTime(String profileId, int addSeconds, String pin) async {
    await _ops.addTime(profileId, addSeconds, pin);
    await refresh();
  }

  /// PIN-gated: overwrites [profileId]'s remaining session seconds.
  Future<void> overrideTime(
    String profileId,
    int remainingSeconds,
    String pin,
  ) async {
    await _ops.overrideTime(profileId, remainingSeconds, pin);
    await refresh();
  }

  /// PIN-gated: enables or disables the TV-wide master lock.
  Future<void> setMasterLock(bool enabled, String pin) async {
    await _ops.setMasterLock(enabled, pin);
    await refresh();
  }

  /// PIN-gated: creates or updates a profile on the TV.
  Future<void> upsertProfile(Profile profile, String pin) async {
    await _ops.upsertProfile(profile, pin);
    await refresh();
  }

  /// One ticker step: burns one wall second from the active session's
  /// remaining time so the rows count down between polls. Stopped when the
  /// TV is offline (there is nothing live to mirror).
  ///
  /// Test hook: the periodic 1-second timer fires on real time; tests that
  /// want to assert between-poll behavior invoke this directly.
  @visibleForTesting
  void tickForTest() => _tick();

  void _tick() {
    if (_disposed || _offline) return;
    final session = _state?.activeSession;
    if (session == null) return;
    final remaining = _state!.remainingByProfile[session.profileId];
    if (remaining == null || remaining <= 0) return;
    _state = _withRemaining(_state!, {..._state!.remainingByProfile}
      ..[session.profileId] = remaining - 1);
    notifyListeners();
  }

  static TvState _withRemaining(TvState st, Map<String, int> remaining) =>
      TvState(
        profiles: st.profiles,
        activeSession: st.activeSession,
        masterLockEnabled: st.masterLockEnabled,
        parentPinSet: st.parentPinSet,
        remainingByProfile: remaining,
        usageByProfile: st.usageByProfile,
        overlayPermissionGranted: st.overlayPermissionGranted,
      );

  /// client.dart maps only SocketException to [EleenOffline]; the
  /// HttpException family can still escape raw (Task 12 finding), so the
  /// controller treats it as offline too.
  static bool _isOffline(Object e) =>
      e is EleenOffline || e is SocketException || e is HttpException;

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _ticker?.cancel();
    super.dispose();
  }
}
