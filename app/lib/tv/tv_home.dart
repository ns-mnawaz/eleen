// The TV home screen: boots the [TvController] (database + LAN server) when
// one is not injected, and shows the [ProfilePicker] — the only main screen.
//
// This is a parental-control dashboard, not a viewing app: enabling a
// child profile's enforcement (the picker's "Enforce time" toggle) starts
// the session in the BACKGROUND while the home stays on screen. A compact
// status row at the top shows who is enforced and how long is left; the
// reminder toasts, last-minute badge and Time's-up lock render over OTHER
// apps via the SYSTEM_ALERT_WINDOW overlay (and in-app while Eleen is
// visible).
//
// The home owns the controller's tick loop (started while a child session
// is enforced, stopped when it ends); a [Timer.periodic] keeps running
// while the app is backgrounded.

import 'dart:async';

import 'package:flutter/material.dart';

import '../platform_launcher.dart';
import '../overlay_permissions.dart';
import '../session_foreground_service.dart';
import '../state/tv_controller.dart';
import 'lock_overlay.dart';
import 'overlay_channel.dart';
import 'pairing_screen.dart';
import 'pin_settings.dart';
import 'profile_picker.dart';
import 'tv_theme.dart';
import 'widgets/last_minute_countdown.dart';
import 'widgets/reminder_toast.dart';

/// TV home. In production (controller == null) this creates a
/// file-backed [TvController] and starts its LAN server on the device's
/// addresses; tests inject a controller backed by an in-memory database and
/// skip the server.
///
/// While the app is backgrounded and the lock is active, the platform
/// (SYSTEM_ALERT_WINDOW) overlay keeps the lock covering the TV — the
/// show/hide platform calls are injectable via the constructor seams
/// (defaults wire flutter_overlay_window) so widget
/// tests never touch the plugin.
///
/// When the lock engages while backgrounded, the home also sends the device
/// to the front over any running app ([bringToFront], default
/// [bringAppToFront]) so YouTube,
/// Netflix) pauses under the lock. It is never sent while Eleen is visible.
///
/// The background overlay isolate also talks to this isolate over the
/// overlay messenger (PIN verification, add-time, switch profile — see
/// overlay_channel.dart): the messenger stream and sender are injectable
/// via [overlayMessages] / [sendOverlayMessage] for the same reason.
class TvHome extends StatefulWidget {
  const TvHome({
    super.key,
    this.controller,
    this.showBackgroundToast,
    this.hideBackgroundToast,
    this.bringToFront,
    this.sessionServiceStart,
    this.sessionServiceStop,
    this.overlayPermissionGranted,
    this.requestOverlayPermission,
    this.sendOverlayMessage,
    this.tickInterval = const Duration(seconds: 1),
  });

  final TvController? controller;

  /// Hides the display-only platform overlay (the toasts/badge surface).
  /// Defaults to [hideToastOverlay].
  final Future<void> Function()? hideBackgroundToast;

  /// Shows the background platform overlay in TOAST mode (transparent,
  /// click-through — a reminder over whatever app is running). Defaults to
  /// [showToastOverlay]; returns whether it was shown.
  final Future<bool> Function()? showBackgroundToast;

  /// Brings the Eleen activity to the front over any running app when the
  /// lock engages while Eleen is backgrounded (a platform overlay cannot
  /// take TV-remote key input, so the interactive lock lives in the real
  /// activity; the running app's activity is paused by the reorder).
  /// Defaults to [bringAppToFront]; injectable for tests.
  final Future<void> Function()? bringToFront;

  /// Starts the session foreground service (defaults to
  /// [SessionForegroundService.start]; injectable for tests).
  final Future<void> Function()? sessionServiceStart;

  /// Stops the session foreground service (defaults to
  /// [SessionForegroundService.stop]; injectable for tests).
  final Future<void> Function()? sessionServiceStop;

  /// Checks the SYSTEM_ALERT_WINDOW permission (defaults to
  /// [overlaysAllowed]; injectable for tests). Enforcement without it is
  /// broken — nothing can render over other apps — so the home shows a
  /// banner routing the parent to the system grant screen.
  final Future<bool> Function()? overlayPermissionGranted;

  /// Opens the system "Display over other apps" grant screen (defaults to
  /// [requestOverlayPermission]; injectable for tests).
  final Future<bool> Function()? requestOverlayPermission;



  /// Pushes a toast/badge message to the overlay isolate (defaults to
  /// [OverlayMessenger.send]).
  final Future<void> Function(Object?)? sendOverlayMessage;

  /// Period of the tick loop driving the live remaining time. Injectable so
  /// widget tests can drive [TvController.tick] by hand instead of waiting
  /// on real time.
  final Duration tickInterval;

  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> with WidgetsBindingObserver {
  TvController? _ownController;
  bool _backgroundLockShown = false;

  /// Whether the HOME intent has been sent for the current background
  /// stretch (the paused/hidden pair would otherwise fire it twice). Reset
  /// when the app resumes.

  /// The transparent click-through platform overlay showing a reminder
  /// toast over another app. Exclusive with the lock overlay (a lock
  /// engaging mid-toast swaps the mode; see [_onControllerChanged]).
  bool _toastOverlayShown = false;
  Timer? _toastCloseTimer;

  /// Whether the platform overlay is currently up for the live last-minute
  /// countdown (the final session minute rendered over another app, pushed
  /// per second). While set, the transient toast close timer must not tear
  /// the overlay down.
  bool _lastMinuteOverlayActive = false;

  /// Whether the session foreground service is currently running (started
  /// while a CHILD session is active so the countdown keeps ticking in the
  /// background; stopped when the session ends, expires or a parent takes
  /// over — parent sessions never burn time).
  bool _sessionServiceRunning = false;

  /// True when enforcement is active (or the lock is up) while the
  /// SYSTEM_ALERT_WINDOW permission is missing: without it, toasts, the
  /// last-minute badge and the lock can never render over other apps — the
  /// home shows a persistent banner until the parent grants it.
  bool _overlayPermissionDenied = false;

  /// The latest permission probe result (null before the first probe
  /// completes): drives the always-visible settings-row status chip and is
  /// published to the coordinator for paired phones.
  bool? _overlayPermissionGranted;

  /// Guards the once-per-session permission probe (the answer is re-checked
  /// on resume — the grant happens in system settings).
  bool _overlayPermissionProbed = false;

  /// Whether the home owns the controller's tick loop right now (started
  /// while a child session is enforced, stopped when it ends). Guarded so a
  /// per-tick notify does not cancel and restart the periodic timer.
  bool _tickerRunning = false;

  /// The in-app reminder toast shown while the home is visible (the
  /// platform overlay owns reminders while backgrounded).
  String? _toastMessage;
  Timer? _inAppToastTimer;

  /// Reminder toasts from the active controller: shown in-app while the
  /// home is visible, forwarded to the platform overlay while backgrounded.
  StreamSubscription<String>? _toastSub;




  /// The controller [_onControllerChanged] is currently attached to (the
  /// controller can be injected late — after bootstrap — or swapped by a
  /// parent rebuild).
  TvController? _listenedController;

  /// The controller in use this build (injected or bootstrapped).
  TvController? get _ctl => widget.controller ?? _ownController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindControllerListener();

    if (widget.controller == null) {
      unawaited(_bootstrap());
    }
    // The status chip needs a probe result even on an idle picker (before
    // any enforcement makes the banner logic care).
    unawaited(_probeOverlayPermission());
  }

  @override
  void didUpdateWidget(TvHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _bindControllerListener();
    }

  }

  /// Attaches the unlock-watcher to the current controller (detaching from
  /// the previous one): the watcher closes the background platform overlay
  /// as soon as the lock clears, even while the app is backgrounded — the
  /// unlock may have come from the parent phone, not from this UI. The same
  /// binding carries the toast subscription (reminders over other apps).
  void _bindControllerListener() {
    final controller = _ctl;
    if (identical(controller, _listenedController)) return;
    _listenedController?.removeListener(_onControllerChanged);
    unawaited(_toastSub?.cancel());
    _listenedController = controller;
    controller?.addListener(_onControllerChanged);
    _toastSub = controller?.toasts.listen(_onControllerToast);
    if (controller != null) _syncTicker(controller);
  }

  /// Starts the tick loop while a child session is enforced (so the live
  /// remaining time on the status row keeps counting down) and stops it
  /// otherwise. Guarded so a per-tick notify does not restart the timer.
  void _syncTicker(TvController controller) {
    final st = controller.state;
    final session = st?.activeSession;
    final childSessionActive = session != null &&
        session.active &&
        st!.profiles
            .where((p) => p.id == session.profileId)
            .any((p) => !p.isParent);
    if (childSessionActive && !_tickerRunning) {
      _tickerRunning = true;
      controller.startTicker(interval: widget.tickInterval);
    } else if (!childSessionActive && _tickerRunning) {
      _tickerRunning = false;
      controller.stopTicker();
    }
  }

  /// One reminder toast fired by the engine thresholds. While the app is
  /// resumed, the home shows it in-app. While backgrounded and nothing is
  /// locked, the platform overlay surfaces it over whatever app is running
  /// (YouTube, ...) in the transparent click-through toast mode.
  Future<void> _onControllerToast(String message) async {
    final controller = _ctl;
    if (controller == null) return;
    if (TvController.isLocked(controller.state)) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      // Visible: show the reminder in-app (transient, like the pill).
      if (!mounted) return;
      setState(() => _toastMessage = message);
      _inAppToastTimer?.cancel();
      _inAppToastTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _toastMessage = null);
      });
      return;
    }

    if (!_toastOverlayShown) {
      _toastOverlayShown = true;
      final shown = await (widget.showBackgroundToast ??
          showToastOverlay)();
      if (!shown) {
        _toastOverlayShown = false;
        return;
      }
    }
    try {
      await (widget.sendOverlayMessage ?? OverlayMessenger.send)(
          {'type': 'toast', 'message': message});
    } catch (error) {
      debugPrint('Eleen: overlay toast push failed: $error');
    }
    // Close the toast overlay a beat after the pill's own 5s lifetime.
    _toastCloseTimer?.cancel();
    _toastCloseTimer = Timer(const Duration(milliseconds: 5500), () {
      if (_toastOverlayShown && !_backgroundLockShown) {
        _toastOverlayShown = false;
        unawaited(
            (widget.hideBackgroundToast ?? hideToastOverlay)());
      }
    });
  }

  void _onControllerChanged() {
    final controller = _ctl;
    if (controller == null) return;
    unawaited(_syncSessionService(controller));
    _syncTicker(controller);
    if (!TvController.isLocked(controller.state)) {
          _backgroundLockShown = false;
      unawaited(_driveLastMinuteOverlay(controller));
      return;
    }
    // A lock engaged while backgrounded: bring the app to the front so the
    // IN-APP lock covers the TV with working remote input (a platform
    // overlay cannot take TV-remote key input) — and the running app's
    // activity is paused, so YouTube/Netflix stop. A toast overlay up at
    // the time closes with it.
    if (_toastOverlayShown) {
      _toastOverlayShown = false;
      _lastMinuteOverlayActive = false;
      _toastCloseTimer?.cancel();
      unawaited(
          (widget.hideBackgroundToast ?? hideToastOverlay)());
    }
    if (_backgroundLockShown) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      unawaited(_engageBackgroundLock());
    }
  }

  /// Brings the Eleen activity to the front for a lock that engaged while
  /// Eleen was backgrounded: the in-app lock covers the TV with working
  /// remote input (a platform overlay cannot take TV-remote key input), and
  /// the running app's activity is paused (YouTube/Netflix stop). Eleen is
  /// never visible here, so the background-activity start is permitted
  /// (SYSTEM_ALERT_WINDOW).
  ///
  /// [_backgroundLockShown] is kept set only while the bring-forward
  /// actually reached the platform. A failed call clears it again so the
  /// next tick retries: latching it would silently disable the lock for the
  /// rest of the background stretch — the child keeps watching YouTube and
  /// nothing ever comes forward. The retry is bounded by the tick loop (at
  /// most one attempt per tick while the lock is engaged).
  Future<void> _engageBackgroundLock() async {
    _backgroundLockShown = true;
    if (!await _bringToFront()) {
      _backgroundLockShown = false;
    }
  }

  /// Runs the bring-to-front seam ([TvHome.bringToFront], default
  /// [bringAppToFront]). Returns whether it succeeded: an injected seam
  /// reports failure by throwing, the default reports it through its result.
  /// Never throws — a platform without the channel must not break the lock.
  Future<bool> _bringToFront() async {
    final seam = widget.bringToFront;
    try {
      if (seam != null) {
        await seam();
        return true;
      }
      return await bringAppToFront();
    } catch (error) {
      debugPrint('Eleen: bringToFront failed: $error');
      return false;
    }
  }

  /// Checks the overlay permission (at startup, on every resume and once
  /// per enforcement session — the grant happens in system settings) and
  /// publishes the result to the coordinator so paired phones can warn.
  /// Denied + something to protect -> the home banner appears; denied at
  /// any time -> the settings-row status chip turns red.
  Future<void> _probeOverlayPermission() async {
    final granted = await (widget.overlayPermissionGranted ??
        overlaysAllowed)();
    if (!mounted) return;
    _ctl?.setOverlayPermissionGranted(granted);
    setState(() {
      _overlayPermissionGranted = granted;
      _overlayPermissionDenied = !granted;
    });
  }

  /// Starts the session foreground service while a CHILD session is active
  /// (the countdown must keep running while the app is backgrounded) and
  /// stops it otherwise. Cheap: guarded by the running flag, this fires on
  /// every controller notification.
  Future<void> _syncSessionService(TvController controller) async {
    final st = controller.state;
    final session = st?.activeSession;
    final childSessionActive = session != null &&
        session.active &&
        st!.profiles
            .where((p) => p.id == session.profileId)
            .any((p) => !p.isParent);
    if (childSessionActive && !_sessionServiceRunning) {
      _sessionServiceRunning = true;
      await (widget.sessionServiceStart ?? SessionForegroundService.start)();
    } else if (!childSessionActive && _sessionServiceRunning) {
      _sessionServiceRunning = false;
      await (widget.sessionServiceStop ?? SessionForegroundService.stop)();
      _overlayPermissionProbed = false;
    }
    // Enforcement (or a lock) without the overlay permission is silently
    // broken for every other app: probe once per session and surface the
    // banner while denied.

    final needsOverlay = childSessionActive ||
        TvController.isLocked(controller.state);
    if (needsOverlay && !_overlayPermissionProbed) {
      _overlayPermissionProbed = true;
      unawaited(_probeOverlayPermission());
    }
  }

  /// Keeps the platform overlay's live last-minute countdown in step with
  /// the active session while the app is backgrounded: entering the final
  /// minute (over another app) shows the click-through overlay and pushes
  /// the remaining seconds every second; leaving it (time added from the
  /// phone, session ended) or the app resuming closes it. Expiry is NOT
  /// handled here — the lock swap path owns that transition.
  Future<void> _driveLastMinuteOverlay(TvController controller) async {
    final session = controller.state?.activeSession;
    final remaining = session?.remainingSeconds ?? 0;
    final inLastMinute =
        session != null && remaining > 0 && controller.coordinator.engine
            .inLastMinute(remaining);

    if (!inLastMinute) {
      if (_lastMinuteOverlayActive) {
        _lastMinuteOverlayActive = false;
        if (_toastOverlayShown) {
          _toastOverlayShown = false;
            unawaited(
              (widget.hideBackgroundToast ?? hideToastOverlay)());
        }
      }
      return;
    }

    // Only while backgrounded: resumed, the status row shows the badge
    // in-app.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) return;

    if (!_toastOverlayShown) {
      _toastOverlayShown = true;
      final shown = await (widget.showBackgroundToast ??
          showToastOverlay)();
      if (!shown) {
        _toastOverlayShown = false;
        return;
      }
    }
    // The last-minute badge persists for the whole final minute: the
    // transient toast's auto-close timer must not tear the overlay down.
    _toastCloseTimer?.cancel();
    _lastMinuteOverlayActive = true;
    try {
      await (widget.sendOverlayMessage ?? OverlayMessenger.send)(
          {'type': 'lastMinute', 'seconds': remaining});
    } catch (error) {
      debugPrint('Eleen: overlay last-minute push failed: $error');
    }
  }

  Future<void> _bootstrap() async {
    final controller = await TvController.forDevice();
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() => _ownController = controller);
    _bindControllerListener();
    // v1.1 D: close the previous run out with the shutdown -> powerOn event
    // pair (usage was capped at its last persisted tick marker). Runs only
    // on the production bootstrap path; injected controllers call it
    // explicitly when a test wants the pair.
    await controller.recoverShutdown();
    // Without this first refresh the picker renders "No profiles yet"
    // forever: the db is never read until a state change happens to call
    // refresh() (widget tests inject an already-refreshed controller, so
    // only the production bootstrap path was affected).
    unawaited(controller.refresh());
    unawaited(controller.startServer());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_toastSub?.cancel());
    _toastCloseTimer?.cancel();
    _inAppToastTimer?.cancel();
    _listenedController?.removeListener(_onControllerChanged);
    if (_tickerRunning) {
      _tickerRunning = false;
      _listenedController?.stopTicker();
    }
    if (_sessionServiceRunning) {
      _sessionServiceRunning = false;
      unawaited(
          (widget.sessionServiceStop ?? SessionForegroundService.stop)());
    }
    _ownController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = widget.controller ?? _ownController;
    if (controller == null) return;
    switch (state) {
      case AppLifecycleState.inactive:
        // Visible but unfocused (a system dialog, the transition into
        // another app): the in-app lock covers the TV; never bring Eleen
        // forward here — a transient inactive (a dialog over the in-app
        // lock) must not eject the parent mid-PIN.
        break;
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        // Fully backgrounded with the lock active (any locked state — master
        // lock or a child session played down to zero — so Home / another
        // app cannot escape the lock): bring the Eleen activity to the
        // front. The in-app lock covers the TV with working remote input,
        // and the running app's activity is paused by the reorder, so an
        // app the child launched (YouTube, Netflix) stops under the lock.
        // Guarded so the hidden -> paused pair brings it forward once.
        if (TvController.isLocked(controller.state) &&
            !_backgroundLockShown) {
          unawaited(_engageBackgroundLock());
        }
      case AppLifecycleState.resumed:
        // The overlay grant happens in system settings: re-probe on every
        // return so the status chip and banner clear as soon as it is
        // granted.
        unawaited(_probeOverlayPermission());
        _backgroundLockShown = false;
        // A pending toast-mode overlay is moot once the app is visible
        // again (the home shows reminders in-app).
        if (_toastOverlayShown) {
          _toastOverlayShown = false;
          _lastMinuteOverlayActive = false;
          _toastCloseTimer?.cancel();
            unawaited((widget.hideBackgroundToast ?? hideToastOverlay)());
        }
      default:
        break;
    }
  }

  /// The parent PIN from the database (`Settings.parentPin` — the source of
  /// truth for the lock overlay's PIN comparison).
  Future<String> _loadParentPin(TvController controller) async =>
      (await controller.coordinator.db.getSettings()).parentPin;

  /// The lock overlay's add-time path: adds [minutes] to the active
  /// session through the coordinator (which re-arms the fired reminder
  /// thresholds) and refreshes. The overlay clears only on success — a
  /// failed add (unknown profile) leaves the remaining time at zero, so
  /// the overlay stays mounted.
  Future<void> _addTime(
    TvController controller,
    String profileId,
    int minutes,
  ) async {
    final remaining = await controller.coordinator.addTime(
      profileId,
      minutes * 60,
    );
    if (remaining != null) {
      await controller.refresh();
    }
  }

  /// Opens the QR pairing screen over the current home content.
  void _openPairing(BuildContext context, TvController controller) {
    unawaited(Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PairingScreen(controller: controller),
    )));
  }

  /// The settings row under the picker: entry points for device setup.
  /// Only reachable while nothing is locked (the lock overlay covers it).
  Widget _settingsRow(BuildContext context, TvController controller) {
    // Wrap, not Row: a narrow window must reflow the entries instead of
    // overflowing.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Wrap(
        spacing: 12,
        children: [
          _overlayPermissionStatusChip(context),
          TextButton.icon(
            key: const Key('settings-pairing'),
            onPressed: () => _openPairing(context, controller),
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Pairing'),
          ),
          TextButton.icon(
            key: const Key('settings-pin'),
            onPressed: () => unawaited(PinSettingsSheet.open(context,
                controller)),
            icon: const Icon(Icons.password),
            label: const Text('Parent PIN'),
          ),
        ],
      ),
    );
  }

  /// The always-visible SYSTEM_ALERT_WINDOW status hint: a chip in the
  /// settings row showing whether the "Display over other apps" permission
  /// is granted, opening the system grant screen on tap (green or red —
  /// the parent can reach the settings link in either state, since the
  /// banner with its full copy only appears while enforcement is active).
  Widget _overlayPermissionStatusChip(BuildContext context) {
    final granted = _overlayPermissionGranted;
    final theme = Theme.of(context);
    final grantedColor = theme.colorScheme.primary;
    final deniedColor = theme.colorScheme.error;
    return TextButton.icon(
      key: const Key('overlay-permission-status'),
      onPressed: () => unawaited(_openOverlayPermissionSettings()),
      icon: Icon(
        granted == false ? Icons.warning_amber_rounded : Icons.check_circle,
        color: granted == false ? deniedColor : grantedColor,
      ),
      label: Text(
        granted == null
            ? 'Overlay permission…'
            : granted
                ? 'Overlays allowed'
                : 'Overlays blocked',
        key: granted == false
            ? const Key('overlay-permission-status-denied')
            : const Key('overlay-permission-status-granted'),
        style: TextStyle(
          color: granted == false ? deniedColor : grantedColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Opens the system "Display over other apps" screen, then re-probes so
  /// the chip/banner reflect the grant as soon as the app resumes.
  Future<void> _openOverlayPermissionSettings() async {
    await (widget.requestOverlayPermission ?? requestOverlayPermission)();
    await _probeOverlayPermission();
  }

  /// The wall-clock time for the compact pill ("8:45 PM"), rebuilt on every
  /// session tick so it stays current.
  String _clockNow() {
    final now = DateTime.now();
    final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$minute $period';
  }

  /// Enforcement without the SYSTEM_ALERT_WINDOW permission is silently
  /// broken for every other app: the reminder toasts, the last-minute
  /// badge and the lock can only render INSIDE Eleen. While denied, this
  /// banner pins to the home until the parent opens the system grant
  /// screen and allows "Display over other apps".
  Widget _overlayPermissionBanner(BuildContext context, Size size) {
    return Container(
      key: const Key('overlay-permission-banner'),
      margin: EdgeInsets.all(size.width * 0.02),
      padding: EdgeInsets.all(size.width * 0.02),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(size.width * 0.02),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: TvType.entry(size.width),
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          SizedBox(width: size.width * 0.015),
          Expanded(
            child: Text(
              'Screen-time overlays can\'t cover other apps yet — allow '
              '"Display over other apps" for Eleen, or the Time\'s up lock '
              'won\'t stop YouTube or Netflix.',
              style: TextStyle(
                fontSize: TvType.body(size.width),
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          SizedBox(width: size.width * 0.015),
          FilledButton.tonal(
            key: const Key('overlay-permission-grant'),
            onPressed: () => unawaited(_openOverlayPermissionSettings()),
            child: Text(
              'Allow overlays',
              style: TextStyle(fontSize: TvType.body(size.width)),
            ),
          ),
        ],
      ),
    );
  }

  /// The compact status row shown at the top of the home while enforcement
  /// is active: who is enforced, the live remaining time (m:ss, ticking) and
  /// the wall-clock pill. Small — it must not dominate the picker.
  Widget _statusRow(
    BuildContext context,
    TvController controller,
    String name,
    int remainingSeconds,
  ) {
    final size = MediaQuery.sizeOf(context);
    final inLastMinute = remainingSeconds > 0 &&
        controller.coordinator.engine.inLastMinute(remainingSeconds);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.04,
        vertical: size.height * 0.015,
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_top,
              size: TvType.body(size.width), color: TvColors.accent),
          SizedBox(width: size.width * 0.01),
          Text(
            name,
            style: TextStyle(
              fontSize: TvType.body(size.width),
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: size.width * 0.02),
          Text(
            formatSessionSeconds(remainingSeconds),
            key: const Key('enforced-remaining'),
            style: TextStyle(
              fontSize: TvType.body(size.width),
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (inLastMinute) ...[
            SizedBox(width: size.width * 0.012),
            LastMinuteCountdown(secondsRemaining: remainingSeconds),
          ],
          const Spacer(),
          Container(
            key: const Key('countdown-compact'),
            padding: EdgeInsets.symmetric(
              horizontal: size.width * 0.015,
              vertical: size.height * 0.008,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(size.width * 0.01),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule,
                    size: TvType.small(size.width), color: TvColors.accent),
                SizedBox(width: size.width * 0.008),
                Text(
                  _clockNow(),
                  style: TextStyle(
                    fontSize: TvType.body(size.width),
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller ?? _ownController;
    if (controller == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final state = controller.state;
          final session = state?.activeSession;
          final activeId = session?.profileId;
          final activeProfile = controller.profiles
              .where((p) => p.id == activeId)
              .firstOrNull;
          final activeName = activeProfile?.name;
          // Enforcement is active while a CHILD session runs; the home keeps
          // showing the picker + settings (no countdown screen) with a
          // compact status row on top.
          final enforced = session != null &&
              session.active &&
              activeProfile != null &&
              !activeProfile.isParent;
          // Lock conditions: the parent master lock covers everything; an
          // expired session covers the home until time is added.
          final masterLock = state?.masterLockEnabled ?? false;
          final locked = TvController.isLocked(state);
          final size = MediaQuery.sizeOf(context);
          return Stack(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    // Only while there is something to protect: the field
                    // documents "enforcement active (or the lock is up)", and
                    // the spec says the banner shows only while enforcement
                    // needs overlays — an ended session must not leave a stale
                    // banner on an idle picker.
                    if (_overlayPermissionDenied && (enforced || locked))
                      _overlayPermissionBanner(context, size),
                    if (enforced)
                      _statusRow(context, controller, activeName ?? '',
                          session.remainingSeconds),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Eleen',
                        style: Theme.of(context)
                            .textTheme
                            .headlineLarge
                            ?.copyWith(color: TvColors.accent),
                      ),
                    ),
                    Expanded(
                      child: ProfilePicker(controller: controller),
                    ),
                    _settingsRow(context, controller),
                  ],
                ),
              ),
              // In-app reminder toast while the home is visible (the
              // platform overlay owns reminders while backgrounded).
              if (_toastMessage != null)
                Positioned(
                  top: size.height * 0.02,
                  left: size.width * 0.04,
                  child: ReminderToast(message: _toastMessage!),
                ),
              // The lock overlay covers 100% of the screen and intercepts
              // Back; the master-lock variant exposes no unlock affordance.
              if (locked)
                Positioned.fill(
                  child: LockOverlay(
                    message: masterLock ? 'Locked by parent' : "Time's up!",
                    masterLock: masterLock,
                    loadParentPin: () => _loadParentPin(controller),
                    onUnlock: activeName == null || activeId == null
                        ? (_) {}
                        : (minutes) => unawaited(
                            _addTime(controller, activeId, minutes),
                          ),
                    // After a correct PIN the parent can also hand the TV to
                    // someone else: ends the expired session (remaining stays
                    // at 0) and shows the profile picker.
                    onSwitchProfile: () =>
                        unawaited(controller.endActiveSession()),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
