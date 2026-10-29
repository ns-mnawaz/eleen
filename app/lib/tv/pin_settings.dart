// TV-side parent-PIN management: opened from the home settings row (next
// to Pairing), so the TV can manage the PIN standalone — no phone needed.
//
// Three flows, driven by whether a PIN is set (read from the db, the source
// of truth):
//
// - No PIN: straight into the SET flow — enter + confirm (two passes of the
//   same D-pad pad).
// - PIN set: a menu with "Change PIN" (current + new + confirm) and
//   "Remove PIN" (current PIN -> cleared, i.e. back to the optional-PIN
//   shape where no gate applies anywhere).
//
// Everything persists through [EngineCoordinator.setParentPin]; other
// settings (token, master lock) are preserved there. The parent PIN is
// never auto-set: it only changes through this sheet or the phone's
// `PUT /api/pin`.
//
// D-pad AND touch friendly: the digits come from the shared [PinPad], and
// every button is focusable and activates on Select/Enter or tap. All sizes
// derive from the sheet's own viewport via a [LayoutBuilder] — no fixed
// pixels — so it fills any TV screen shape.

import 'package:flutter/material.dart';

import '../state/tv_controller.dart';
import 'tv_theme.dart';
import 'widgets/pin_pad.dart';

/// Full-screen parent-PIN management. Push it with [PinSettingsSheet.open].
class PinSettingsSheet extends StatefulWidget {
  const PinSettingsSheet({super.key, required this.controller});

  final TvController controller;

  /// Opens the sheet as a full-screen route over the TV home.
  static Future<void> open(BuildContext context, TvController controller) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PinSettingsSheet(controller: controller),
      ));

  @override
  State<PinSettingsSheet> createState() => _PinSettingsSheetState();
}

/// The stages of the active flow. `menu` only shows when a PIN is set.
enum _Stage {
  menu,
  /// Enter the current PIN (change/remove flows).
  current,

  /// Enter the new PIN.
  newPin,

  /// Re-enter the new PIN.
  confirm,

  /// Terminal: the change landed.
  done,
}

class _PinSettingsSheetState extends State<PinSettingsSheet> {
  _Stage _stage = _Stage.menu;
  bool _removing = false;
  String _entry = '';
  String? _error;
  bool _busy = false;

  /// The Next/Save button's node: when the 4th digit lands (new-PIN and
  /// confirm stages), D-pad focus jumps here so the parent can just press
  /// Select — no arrow walk from the pad's last key.
  final FocusNode _nextFocus = FocusNode(debugLabel: 'pin-settings-next');

  /// A digit was pressed while the entry already held the full 4 digits.
  /// PINs are exactly 4 digits, so the extra key does not extend the entry;
  /// it flags the attempt so Next rejects it (see [_onDigit] / [_next]).
  bool _overflow = false;

  /// The PIN for the current/validate stages (read once per flow; the db is
  /// the source of truth).
  String? _storedPin;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Decides the entry stage: no PIN set -> straight into the set flow.
  Future<void> _bootstrap() async {
    final pin = (await widget.controller.coordinator.db.getSettings()).parentPin;
    if (!mounted) return;
    setState(() {
      _storedPin = pin;
      _stage = pin.isEmpty ? _Stage.newPin : _Stage.menu;
    });
  }

  String get _title {
    switch (_stage) {
      case _Stage.menu:
        return 'Parent PIN';
      case _Stage.current:
        return _removing
            ? 'Enter the current PIN to remove it'
            : 'Enter the current PIN';
      case _Stage.newPin:
        return _storedPin!.isEmpty ? 'Set a parent PIN' : 'Enter the new PIN';
      case _Stage.confirm:
        return 'Confirm the new PIN';
      case _Stage.done:
        return _removing ? 'PIN removed' : 'PIN saved';
    }
  }

  void _reset({bool clearStored = false}) {
    setState(() {
      _entry = '';
      _error = null;
      _overflow = false;
      if (clearStored) _storedPin = null;
    });
  }

  Future<void> _startChange() async {
    _reset();
    setState(() => _stage = _Stage.current);
  }

  Future<void> _startRemove() async {
    _reset();
    setState(() {
      _removing = true;
      _stage = _Stage.current;
    });
  }

  /// The Next/Save/Remove button: advances the current stage.
  Future<void> _next() async {
    if (_busy) return;
    switch (_stage) {
      case _Stage.menu:
        return;
      case _Stage.current:
        if (_entry != _storedPin) {
          setState(() {
            _error = 'Wrong PIN';
            _entry = '';
            _overflow = false;
          });
          return;
        }
        if (_removing) {
          await _save('');
          return;
        }
        setState(() {
          _stage = _Stage.newPin;
          _entry = '';
          _error = null;
          _overflow = false;
        });
        return;
      case _Stage.newPin:
        // Exactly 4 digits: a pressed-but-ignored 5th key flags the attempt.
        if (_overflow) {
          setState(() => _error = 'Use no more than 4 digits');
          return;
        }
        if (_entry.length < 4) {
          setState(() => _error = 'Use at least 4 digits');
          return;
        }
        // Changing the PIN to its current value is a no-op: reject it.
        final stored = _storedPin;
        if (stored != null && stored.isNotEmpty && _entry == stored) {
          setState(
              () => _error = 'New PIN must be different from the current PIN');
          return;
        }
        _firstEntry = _entry;
        setState(() {
          _stage = _Stage.confirm;
          _entry = '';
          _error = null;
          _overflow = false;
        });
        return;
      case _Stage.confirm:
        if (_entry != _firstEntry) {
          setState(() {
            _error = 'PINs do not match';
            _entry = '';
            _overflow = false;
            _stage = _Stage.newPin;
          });
          return;
        }
        await _save(_firstEntry);
        return;
      case _Stage.done:
        return;
    }
  }

  /// The new PIN entered in the `newPin` stage, carried into `confirm`.
  String _firstEntry = '';

  /// One digit entered on the current entry stage. The PIN is exactly 4
  /// digits: a 5th key does not extend the entry — it flags the overflow so
  /// Next rejects the attempt (and the entry stays intact for correction).
  ///
  /// The `current` stage caps at the STORED PIN's length instead: a legacy
  /// database may still hold a longer PIN (set before the exactly-4 rule),
  /// and capping that stage at 4 would make Change/Remove permanently
  /// unable to match it — a lockout.
  Future<void> _onDigit(String digit) async {
    if (_busy || _stage == _Stage.menu || _stage == _Stage.done) return;
    final cap = _stage == _Stage.current
        ? (_storedPin?.isEmpty == false ? _storedPin!.length : 4)
        : 4;
    if (_entry.length >= cap) {
      setState(() {
        _overflow = true;
        _error = 'Use no more than $cap digits';
      });
      return;
    }
    setState(() {
      _entry += digit;
      _overflow = false;
      _error = null;
    });
    // Full 4-digit entry on the new-PIN/confirm stages: hand D-pad focus to
    // the action button (post-frame: the button may not be built yet at the
    // first digit's frame).
    if (_stage != _Stage.current && _entry.length == 4) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_busy) _nextFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _nextFocus.dispose();
    super.dispose();
  }

  Future<void> _save(String pin) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.coordinator.setParentPin(pin);
      await widget.controller.refresh();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stage = _Stage.done;
        _entry = '';
        _overflow = false;
        _storedPin = pin.isEmpty ? null : pin;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save the PIN: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // All sizes derive from the sheet's own viewport, never fixed pixels.
    return Scaffold(
      key: const Key('pin-settings'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Padding(
                  padding: EdgeInsets.all(w * 0.04),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _title,
                        style: TextStyle(
                          fontSize: TvType.title(w),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: TvSpace.md(h)),
                      if (_stage == _Stage.menu) ...[
                        Text(
                          'A parent PIN gates every parent action on this '
                          'TV. With none set, no PIN is ever asked for.',
                          style: TextStyle(fontSize: TvType.body(w)),
                        ),
                        SizedBox(height: TvSpace.lg(h)),
                        FilledButton(
                          key: const Key('pin-settings-change'),
                          onPressed: _startChange,
                          child: Text('Change PIN',
                              style: TextStyle(fontSize: TvType.body(w))),
                        ),
                        SizedBox(height: TvSpace.sm(h)),
                        OutlinedButton(
                          key: const Key('pin-settings-remove'),
                          onPressed: _startRemove,
                          child: Text('Remove PIN',
                              style: TextStyle(fontSize: TvType.body(w))),
                        ),
                        SizedBox(height: TvSpace.lg(h)),
                        TextButton(
                          key: const Key('pin-settings-cancel'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Back'),
                        ),
                      ] else if (_stage == _Stage.done) ...[
                        FilledButton(
                          key: const Key('pin-settings-done'),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ] else ...[
                        Text(
                          '•' * _entry.length,
                          style: TextStyle(
                            fontSize: TvType.entry(w),
                            letterSpacing: w * 0.01,
                          ),
                        ),
                        if (_error != null)
                          Text(
                            key: const Key('pin-settings-error'),
                            _error!,
                            style: TextStyle(
                              color: TvColors.error,
                              fontSize: TvType.body(w),
                            ),
                          ),
                        SizedBox(height: TvSpace.md(h)),
                        // Cap the pad's height so the action row below it
                        // stays inside a 540p viewport (BUG-2): the natural
                        // width-proportional pad pushed Cancel/Next ~55px
                        // below the fold on 960x540 TVs.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: h * TvPinPad.sheetHeightFraction,
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: PinPad(onDigit: _onDigit),
                          ),
                        ),
                        SizedBox(height: TvSpace.md(h)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              key: const Key('pin-settings-cancel'),
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              child: const Text('Cancel'),
                            ),
                            SizedBox(width: w * 0.02),
                            FilledButton(
                              key: const Key('pin-settings-next'),
                              focusNode: _nextFocus,
                              onPressed: _busy ? null : _next,
                              child: Text(
                                _removing && _stage == _Stage.current
                                    ? 'Remove'
                                    : _stage == _Stage.confirm
                                        ? 'Save'
                                        : 'Next',
                                style: TextStyle(fontSize: TvType.body(w)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
