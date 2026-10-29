// The TV lock overlay: what the child sees when time is up (or when the
// parent has master-locked the TV).
//
// Two variants share this one widget so they render identically:
//
// - Unlockable (time's up): D-pad PIN entry; the correct PIN (compared
//   against `Settings.parentPin` in the database, never hardcoded — the
//   caller supplies [loadParentPin]) reveals an "Add 15 / 30 minutes"
//   chooser that reports the choice through [onUnlock]. A wrong PIN shows
//   an error and the overlay stays. The overlay only clears when the
//   caller's add-time path succeeds (the mount removes it once the
//   remaining time is back above zero). The PIN is optional: with none set
//   the chooser shows immediately and no pad is rendered.
//
// - Master lock: same overlay, "Locked by parent" copy, and no unlock
//   affordance at all — the PIN pad is not shown; unlock comes only from
//   the parent phone.
//
// Both variants rotate a generated gradient slideshow behind a scrim so the
// lock screen stays gentle without hurting readability (see
// widgets/lock_slideshow.dart).
//
// The overlay covers 100% of the screen at any resolution (sizes are
// proportional to [MediaQuery]) and intercepts Back via [PopScope].
//
// This file also holds [BackgroundReminderOverlay]: the DISPLAY-ONLY
// content of the platform overlay engine (`overlayMain` in main.dart) —
// the reminder toast pill and the live last-minute badge over whatever app
// is running. The interactive lock is deliberately NOT an overlay: a
// platform window cannot take TV-remote key input, so a lock while
// backgrounded brings the Eleen activity to the front instead.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'overlay_channel.dart';
import 'tv_theme.dart';
import 'widgets/lock_slideshow.dart';
import 'widgets/pin_pad.dart';
import 'widgets/reminder_toast.dart';
import 'widgets/last_minute_countdown.dart';

/// Content for the plugin-spawned platform-overlay engine: DISPLAY ONLY.
/// While the app is backgrounded and nothing is locked, the main isolate
/// pushes reminder toasts and the live last-minute countdown over the
/// channel (see [OverlayChannelClient] in overlay_channel.dart) and this
/// renders them over whatever app is running — fully transparent and
/// click-through otherwise. The interactive lock is deliberately NOT here:
/// a platform overlay window cannot take TV-remote key input, so a lock
/// while backgrounded brings the Eleen activity to the front instead.
///
/// Wired by `overlayMain` in `main.dart`: the plugin resolves that
/// entrypoint by name from the app's root library only.
class BackgroundReminderOverlay extends StatefulWidget {
  const BackgroundReminderOverlay({super.key, this.client});

  /// Injectable push client (tests supply a fake main isolate). Defaults to
  /// a real [OverlayChannelClient] over flutter_overlay_window's messenger.
  final OverlayChannelClient? client;

  @override
  State<BackgroundReminderOverlay> createState() =>
      _BackgroundReminderOverlayState();
}

class _BackgroundReminderOverlayState extends State<BackgroundReminderOverlay> {
  OverlayChannelClient? _ownClient;

  /// A reminder toast pushed by the main isolate while another app runs
  /// ("10 minutes left"): shown for ~5 seconds.
  String? _toastMessage;
  Timer? _toastTimer;

  /// The live last-minute countdown pushed per second by the main isolate
  /// (the final session minute). Null = not in the final minute. Cleared by
  /// a seconds <= 0 push (time added from the phone, session ended).
  int? _lastMinuteSeconds;

  StreamSubscription<String>? _toastSub;
  StreamSubscription<int>? _lastMinuteSub;

  OverlayChannelClient get _client => widget.client ?? _ownClient!;

  @override
  void initState() {
    super.initState();
    if (widget.client == null) {
      _ownClient = OverlayChannelClient();
    }
    _client.listen();
    _toastSub = _client.toastPushes.listen(_onToastPush);
    _lastMinuteSub = _client.lastMinutePushes.listen(_onLastMinutePush);
  }

  void _onToastPush(String message) {
    if (!mounted) return;
    setState(() => _toastMessage = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  void _onLastMinutePush(int seconds) {
    if (!mounted) return;
    setState(() => _lastMinuteSeconds = seconds > 0 ? seconds : null);
  }

  @override
  void dispose() {
    unawaited(_toastSub?.cancel());
    unawaited(_lastMinuteSub?.cancel());
    _toastTimer?.cancel();
    _ownClient?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Transparent + click-through (the flag is set by the platform show
    // call): the running app stays fully visible and usable around the pills.
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            if (_toastMessage != null)
              _ToastPill(message: _toastMessage!),
            if (_lastMinuteSeconds != null)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(
                      MediaQuery.sizeOf(context).width * 0.04),
                  child: LastMinuteCountdown(
                      secondsRemaining: _lastMinuteSeconds!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One reminder pill for the display-only platform overlay: the same
/// [ReminderToast] the in-app home shows (top-left corner, identical
/// presentation on every surface).
class _ToastPill extends StatelessWidget {
  const _ToastPill({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: EdgeInsets.all(size.width * 0.04),
        child: ReminderToast(message: message),
      ),
    );
  }
}

/// Full-screen lock. [message] is the headline ("Time's up!" / "Locked by
/// parent"); [onUnlock] is called with the chosen number of minutes (15 or
/// 30) after a correct PIN; [loadParentPin] fetches the parent PIN from the
/// database for comparison. With [masterLock] set, no unlock affordance is
/// rendered.
///
/// [verifyPin] overrides the local comparison with an injected verifier
/// (the background overlay verifies against the main isolate over a
/// channel). When set, [loadParentPin] is only consulted for emptiness ("is
/// a PIN set at all?") — its value is never compared.
class LockOverlay extends StatefulWidget {
  const LockOverlay({
    super.key,
    required this.message,
    required this.onUnlock,
    required this.loadParentPin,
    this.masterLock = false,
    this.onSwitchProfile,
    this.verifyPin,
  });

  final String message;

  /// Called with 15 or 30 once the PIN is accepted and the parent picks an
  /// add-time amount. The overlay clears when the caller's add-time path
  /// succeeds and the remaining time rises above zero.
  final ValueChanged<int> onUnlock;

  /// Optional: called (after a correct PIN) when the parent picks "Switch
  /// profile" — ends the expired session so the profile picker shows. When
  /// null, the option is not offered.
  final VoidCallback? onSwitchProfile;

  /// Fetches `Settings.parentPin` (the db is the source of truth, so the
  /// comparison is never against a hardcoded value).
  final Future<String> Function() loadParentPin;

  /// Parent master lock: show the copy but no PIN pad or chooser.
  final bool masterLock;

  /// Optional remote/override verifier (see [PinVerifier]). When non-null
  /// it decides acceptance entirely; [loadParentPin] then only reports
  /// whether a PIN is set.
  final PinVerifier? verifyPin;

  @override
  State<LockOverlay> createState() => _LockOverlayState();
}

class _LockOverlayState extends State<LockOverlay> {
  String _entry = '';
  String? _error;
  bool _pinAccepted = false;

  /// Serializes digit handling: each press is processed after the previous
  /// one's (possibly async, possibly remote) check completed, so entries
  /// accumulate in press order even when checks take a round-trip.
  Future<void> _digitQueue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    // The PIN is optional: with none set the unlockable overlay skips the
    // pad entirely and offers the add-time chooser straight away. The check
    // is async (db read); until it lands the pad renders, exactly as when a
    // PIN is set.
    unawaited(_skipPadWhenUnset());
  }

  Future<void> _skipPadWhenUnset() async {
    if (widget.masterLock) return;
    final pin = await widget.loadParentPin();
    if (!mounted || widget.masterLock || pin.isNotEmpty) return;
    setState(() => _pinAccepted = true);
  }

  /// Checks [entry] against the PIN source: the injected verifier when set
  /// (e.g. the background overlay's main-isolate round-trip), otherwise a
  /// local full-match comparison against the loaded parent PIN.
  Future<PinCheck> _checkEntry(String entry) async {
    final verifier = widget.verifyPin;
    if (verifier != null) return verifier(entry);
    final pin = await widget.loadParentPin();
    if (pin.isEmpty) {
      // No PIN has been set: there is nothing to compare against — the
      // parent proceeds without a gate (normally the initState check has
      // already swapped the pad for the chooser).
      return const PinCheck.accepted();
    }
    if (entry.length < pin.length) {
      // Still entering: no correctness signal until the attempt is complete.
      return const PinCheck.incomplete();
    }
    return PinCheck(accepted: pin == entry, complete: true);
  }

  /// One digit entered (queued — see [_digitQueue]). The entry is compared
  /// against the parent PIN only once it has reached the PIN's full length
  /// — one full-match check per attempt, no per-press correctness feedback
  /// (an incremental prefix check would let a methodical child recover the
  /// PIN digit by digit). A wrong attempt shows the error and keeps the
  /// overlay up.
  /// The lock screen's always-visible "Switch profile" button: it is a
  /// parent action, so with a PIN set it points at the pad (the chooser —
  /// with the real switch — appears after the correct PIN). With no PIN set
  /// the overlay already skipped to the chooser, so this is never reachable
  /// ungated.
  void _switchDirect() {
    if (_pinAccepted) {
      widget.onSwitchProfile?.call();
      return;
    }
    setState(() => _error = 'Enter the parent PIN first');
  }

  void _onDigit(String digit) {
    unawaited(_digitQueue = _digitQueue.then((_) => _processDigit(digit)));
  }

  Future<void> _processDigit(String digit) async {
    if (!mounted || widget.masterLock || _pinAccepted) return;
    final entry = _entry + digit;
    final check = await _checkEntry(entry);
    if (!mounted || widget.masterLock || _pinAccepted) return;

    if (check.accepted) {
      setState(() {
        _pinAccepted = true;
        _error = null;
        _entry = '';
      });
      return;
    }
    if (!check.complete) {
      // Still entering: extend the entry, but do NOT clear an existing
      // wrong-PIN error — it stays until the next COMPLETE attempt, so a
      // wrong attempt followed by extra keys keeps reporting the failure
      // (and the pad stays usable for a retry).
      setState(() {
        _entry = entry;
      });
      return;
    }
    setState(() {
      _error = 'Wrong PIN';
      _entry = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    // All sizes proportional to the screen, never fixed pixels.
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      // Back must not dismiss the lock.
      canPop: false,
      child: Material(
        // Ink features (InkWell) and filled buttons need a Material
        // ancestor; the overlay renders on an opaque sheet over the
        // slideshow.
        type: MaterialType.transparency,
        child: Container(
          key: const Key('lock-overlay'),
          color: TvColors.background,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Slow generated gradient scenes, then a scrim so text and
              // pad stay fully readable over them.
              const LockSlideshow(),
              const IgnorePointer(
                child: ColoredBox(key: Key('lock-scrim'), color: TvColors.scrim),
              ),
              SafeArea(
                // Scroll-safe: at small TV resolutions the pad + message can
                // exceed the viewport by a few pixels, which must degrade to
                // a scroll instead of a hard overflow. When it fits, the
                // minHeight-constrained column still centers the content.
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.message,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: TvColors.onDark,
                              fontSize: TvType.headline(size.width),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.masterLock) ...[
                            SizedBox(height: TvSpace.sm(size.height)),
                            Text(
                              'Unlock from the parent phone app',
                              style: TextStyle(
                                color: TvColors.onDarkMuted,
                                fontSize: TvType.body(size.width),
                              ),
                            ),
                          ] else if (_pinAccepted) ...[
                            SizedBox(height: TvSpace.sm(size.height)),
                            // Hand-over hint: a family member can add time
                            // or hand the TV over without the phone.
                            Text(
                              key: const Key('lock-hint'),
                              'Choose to add time or switch profiles',
                              style: TextStyle(
                                color: TvColors.onDarkMuted,
                                fontSize: TvType.body(size.width),
                              ),
                            ),
                            SizedBox(height: TvSpace.lg(size.height)),
                            _buildChooser(),
                          ] else ...[
                            SizedBox(height: TvSpace.sm(size.height)),
                            // Hand-over hint: entering the parent PIN leads
                            // to add-time or profile switch, not just
                            // unlocking.
                            Text(
                              key: const Key('lock-hint'),
                              'Enter parent PIN to add time or switch profiles',
                              style: TextStyle(
                                color: TvColors.onDarkMuted,
                                fontSize: TvType.body(size.width),
                              ),
                            ),
                            SizedBox(height: TvSpace.md(size.height)),
                            Text(
                              '•' * _entry.length,
                              style: TextStyle(
                                color: TvColors.onDark,
                                fontSize: TvType.entry(size.width),
                                letterSpacing: size.width * 0.01,
                              ),
                            ),
                            if (_error != null)
                              Text(
                                key: const Key('pin-error'),
                                _error!,
                                style: TextStyle(
                                  color: TvColors.error,
                                  fontSize: TvType.body(size.width),
                                ),
                              ),
                            SizedBox(height: TvSpace.md(size.height)),
                            // Cap the pad's height so the '0' row stays
                            // tappable inside a 540p viewport (BUG-3): the
                            // natural width-proportional pad put the '0'
                            // cell's center just below the fold.
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight *
                                    TvPinPad.overlayHeightFraction,
                              ),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: PinPad(onDigit: _onDigit),
                              ),
                            ),
                            if (widget.onSwitchProfile != null)
                              Padding(
                                padding:
                                    EdgeInsets.only(top: TvSpace.md(size.height)),
                                child: OutlinedButton(
                                  key: const Key('lock-switch-direct'),
                                  onPressed: _switchDirect,
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      vertical: size.height * 0.012,
                                      horizontal: size.width * 0.02,
                                    ),
                                    child: Text(
                                      'Switch profile',
                                      style: TextStyle(
                                          fontSize: TvType.entry(size.width)),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChooser() {
    final size = MediaQuery.sizeOf(context);
    Widget button(int minutes, String label, {bool autofocus = false}) {
      return FilledButton(
        key: Key('unlock-$minutes'),
        autofocus: autofocus,
        onPressed: () => widget.onUnlock(minutes),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: size.height * 0.012,
            horizontal: size.width * 0.02,
          ),
          child: Text(label, style: TextStyle(fontSize: TvType.button(size.width))),
        ),
      );
    }

    // D-pad center arrives as Select; accept Enter too for emulators.
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: Wrap(
        // Wrap (not a Row) so the two choices reflow instead of overflowing
        // on any screen width.
        alignment: WrapAlignment.center,
        spacing: size.width * 0.03,
        runSpacing: size.height * 0.02,
        children: [
          // The pad just unmounted, so D-pad focus must move here
          // immediately — otherwise the chooser is tap-only.
          button(15, 'Add 15 minutes', autofocus: true),
          button(30, 'Add 30 minutes'),
          if (widget.onSwitchProfile != null)
            OutlinedButton(
              key: const Key('unlock-switch'),
              onPressed: widget.onSwitchProfile,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: size.height * 0.012,
                  horizontal: size.width * 0.02,
                ),
                child: Text(
                  'Switch profile',
                  style: TextStyle(fontSize: TvType.button(size.width)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
