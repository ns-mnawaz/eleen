// The TV profile picker: a D-pad-focusable grid of profiles.
//
// The grid is proportional — cell sizes derive from the available space via
// a [LayoutBuilder], never from fixed pixel sizes — so it fills any TV
// screen shape.
//
// Enforcement: each card carries an "Enforce time" toggle (the core
// interaction now that the app is a background parental-control dashboard,
// not a viewing app). Toggling a card ON makes it the ONE enforced profile
// (any other active session ends first) and starts its session; toggling
// OFF ends the active session. Tapping a card also enables enforcement.
//
// The parent PIN gates management: when a PIN is set, toggling enforcement
// and opening the form (add/edit) both demand the PIN (same D-pad pad as
// the lock overlay). A wrong PIN shows an error and the action does not
// happen. With NO PIN set (the PIN is optional) every gate is bypassed.
//
// Profile management: an "Add profile" card sits last in the grid, and a
// long-press on a card (touch, or holding Select/Enter on the D-pad) opens
// its editor — behind the same PIN gate, so the form needs no PIN logic.

import 'dart:async';
import 'dart:math' as math;

import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/tv_controller.dart';
import 'profile_form.dart';
import 'tv_theme.dart';
import 'widgets/pin_pad.dart';

/// What the PIN gate is currently guarding.
enum _GateKind {
  /// Opening the profile form (create when the target is null, edit of the
  /// target otherwise).
  form,

  /// Flipping a card's enforcement toggle to [value].
  toggle,
}

/// An open PIN gate: [profile] is the edit target for [_GateKind.form]
/// (null = create) or the toggled card for [_GateKind.toggle].
class _Gate {
  const _Gate.form(this.profile)
      : kind = _GateKind.form,
        value = null;
  const _Gate.toggle(this.profile, this.value) : kind = _GateKind.toggle;

  final _GateKind kind;
  final Profile? profile;

  /// The desired enforcement state for a [_GateKind.toggle] gate.
  final bool? value;
}

/// Grid of avatars + names for every profile on the controller.
//
/// Toggling a card's "Enforce time" switch (or tapping the card) starts
/// enforcement for that profile — after the parent PIN gate when one is
/// set. The trailing add-profile card and card long-press open the
/// [ProfileForm], behind the same gate.
class ProfilePicker extends StatefulWidget {
  const ProfilePicker({
    super.key,
    required this.controller,
    this.onProfileSelected,
    this.loadParentPin,
  });

  final TvController controller;

  final void Function(Profile profile)? onProfileSelected;

  /// Fetches `Settings.parentPin` for the management gate. Defaults to
  /// reading the controller's database (the same source of truth the lock
  /// overlay uses).
  final Future<String> Function()? loadParentPin;

  @override
  State<ProfilePicker> createState() => _ProfilePickerState();
}

class _ProfilePickerState extends State<ProfilePicker> {
  /// The open PIN gate, or null while the plain grid shows.
  _Gate? _gate;

  Future<String> _defaultLoadParentPin() async =>
      (await widget.controller.coordinator.db.getSettings()).parentPin;

  Future<String> _loadPin() async {
    final load = widget.loadParentPin ?? _defaultLoadParentPin;
    return load();
  }

  /// The gate prompt's headline for [gate].
  String _gateTitle(_Gate gate) {
    switch (gate.kind) {
      case _GateKind.toggle:
        return 'Enter parent PIN to manage profiles';
      case _GateKind.form:
        return gate.profile == null
            ? 'Enter parent PIN to manage profiles'
            : 'Enter parent PIN to edit ${gate.profile!.name}';
    }
  }

  /// Requests a change to [profile]'s enforcement (the switch or a card
  /// tap), behind the parent-PIN gate when one is set. With no PIN set the
  /// change applies directly.
  Future<void> _requestEnforce(Profile profile, bool value) async {
    final pin = await _loadPin();
    if (!mounted) return;
    if (pin.isEmpty) {
      await _applyEnforce(profile, value);
      return;
    }
    // Hand focus straight to the PIN pad: the tapped/D-pad-activated card
    // keeps primary focus otherwise, making the pad's autofocus a no-op and
    // D-pad PIN entry dead on arrival.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _gate = _Gate.toggle(profile, value));
  }

  /// Applies an enforcement change: ON makes [profile] the one enforced
  /// profile (any other active session ends first, inside
  /// [TvController.selectProfile]); OFF ends the active session.
  Future<void> _applyEnforce(Profile profile, bool value) async {
    if (value) {
      await widget.controller.selectProfile(profile.id);
      widget.onProfileSelected?.call(profile);
    } else {
      await widget.controller.endActiveSession();
    }
  }

  /// Requests the profile form (create when [existing] is null) behind the
  /// parent-PIN gate. With no PIN set the form opens directly — the gate
  /// only exists when there is a PIN to check.
  Future<void> _requestForm(Profile? existing) async {
    final pin = await _loadPin();
    if (!mounted) return;
    if (pin.isEmpty) {
      await _openForm(existing);
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _gate = _Gate.form(existing));
  }

  Future<void> _openForm(Profile? existing) async {
    // Hand focus to the form: the tapped/D-pad-activated card keeps primary
    // focus otherwise, so the form's avatar autofocus is a no-op and the
    // D-pad drives the picker behind the modal form (the exact failure the
    // gate path above avoids). Mirrors the gate's unfocus.
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ProfileForm(
        controller: widget.controller,
        existing: existing,
      ),
    ));
  }

  Future<void> _onPinDigit(String digit) async {
    if (!mounted || _gate == null) return;
    final pin = await _loadPin();
    if (!mounted || _gate == null) return;

    if (pin.isEmpty) {
      // Defensive: the gate only opens when a PIN is set (and the PIN is
      // managed on this TV now). If it vanished mid-entry, close the gate.
      _cancelPin();
      return;
    }

    final entry = _entry + digit;
    if (entry.length < pin.length) {
      // Still entering: no correctness signal until the attempt is complete
      // (mirrors the lock overlay — no digit-by-digit feedback).
      setState(() {
        _entry = entry;
        _error = null;
      });
      return;
    }
    if (entry == pin) {
      final gate = _gate!;
      setState(() {
        _entry = '';
        _error = null;
        _gate = null;
      });
      if (gate.kind == _GateKind.toggle) {
        await _applyEnforce(gate.profile!, gate.value!);
      } else {
        await _openForm(gate.profile);
      }
      return;
    }
    setState(() {
      _entry = '';
      _error = 'Wrong PIN';
    });
  }

  String _entry = '';
  String? _error;

  void _cancelPin() => setState(() {
    _gate = null;
    _entry = '';
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final profiles = widget.controller.profiles;
        final activeId = widget.controller.state?.activeSession?.profileId;
        // The empty picker is not a dead end: the add card is still offered
        // (behind the same gate) so the TV can provision its first profile.
        final content = profiles.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No profiles yet'),
                    _AddProfileCard(
                      key: const Key('add-profile-card'),
                      autofocus: true,
                      onSelected: () => _requestForm(null),
                    ),
                  ],
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  // Column count is derived from the available aspect ratio,
                  // not from pixels: a 16:9 TV gets 4 columns, a narrow
                  // window fewer.
                  final aspect = constraints.maxWidth /
                      math.max(constraints.maxHeight, 1);
                  final columns = math.max(2, (aspect * 2).round());
                  return GridView.builder(
                    gridDelegate:
                        SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      childAspectRatio: 1,
                    ),
                    // One extra cell: the add-profile card, always last.
                    itemCount: profiles.length + 1,
                    itemBuilder: (context, index) {
                      if (index == profiles.length) {
                        return _AddProfileCard(
                          key: const Key('add-profile-card'),
                          autofocus: false,
                          onSelected: () => _requestForm(null),
                        );
                      }
                      final profile = profiles[index];
                      return _ProfileCard(
                        key: Key('profile-card-${profile.id}'),
                        profile: profile,
                        remainingSeconds: widget
                            .controller.state?.remainingByProfile[profile.id],
                        enforced: activeId == profile.id,
                        autofocus: index == 0,
                        // A tap or a D-pad Select enables enforcement for
                        // this profile (the switch below also toggles it).
                        onSelected: () => _requestEnforce(profile, true),
                        onToggle: (value) => _requestEnforce(profile, value),
                        onEdit: () => _requestForm(profile),
                      );
                    },
                  );
                },
              );
        final gate = _gate;
        // Always a Stack: returning `content` directly when the gate is null
        // and a Stack when it is not would change the widget type at this
        // position, so Flutter would tear down and rebuild the whole grid on
        // every gate open/close. That rebuild re-fires the first card's
        // `autofocus`, stealing focus back to the picker behind the modal
        // form (BUG-1). A stable tree keeps the grid's focus state intact.
        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (gate != null)
              Positioned.fill(
                child: _ParentPinPrompt(
                  key: const Key('parent-pin-prompt'),
                  title: _gateTitle(gate),
                  entry: _entry,
                  error: _error,
                  onDigit: _onPinDigit,
                  onCancel: _cancelPin,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The PIN gate over the grid while a parent selection or a form (create or
/// edit) is pending: the same D-pad pad as the lock overlay, with a "wrong
/// PIN" error that leaves the prompt up for a retry.
class _ParentPinPrompt extends StatelessWidget {
  const _ParentPinPrompt({
    super.key,
    required this.title,
    required this.entry,
    required this.error,
    required this.onDigit,
    required this.onCancel,
  });

  final String title;
  final String entry;
  final String? error;
  final ValueChanged<String> onDigit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    // All sizes derive from the prompt's OWN viewport (LayoutBuilder
    // constraints), never from full-screen MediaQuery and never from fixed
    // pixels: the prompt covers the picker's share of the screen, which is
    // smaller than a full-screen overlay's.
    return Container(
      color: TvColors.modalScrim,
      alignment: Alignment.center,
      // A fresh scope for the prompt: the pad's autofocus is resolved
      // against THIS scope (whose focusedChild is null on mount) instead of
      // the picker's scope, where the selected card may still be the
      // focused child and would silently discard the autofocus request.
      child: FocusScope(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            // Scroll-safe: if the content ever exceeds the viewport it
            // degrades to a scroll instead of an overflow (same treatment as
            // the lock overlay).
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: TvColors.onDark,
                        fontSize: TvType.title(w),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: TvSpace.sm(h)),
                    Text(
                      '•' * entry.length,
                      style: TextStyle(
                        color: TvColors.onDark,
                        fontSize: TvType.button(w),
                        letterSpacing: w * 0.01,
                      ),
                    ),
                    if (error != null)
                      Text(
                        key: const Key('pin-error'),
                        error!,
                        style: TextStyle(
                          color: TvColors.error,
                          fontSize: TvType.body(w),
                        ),
                      ),
                    SizedBox(height: TvSpace.sm(h)),
                    // The pad scales down to the space it actually has;
                    // FittedBox keeps it proportional.
                    SizedBox(
                      height: h * 0.55,
                      width: w * 0.5,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: PinPad(onDigit: onDigit),
                      ),
                    ),
                    SizedBox(height: TvSpace.sm(h)),
                    TextButton(
                      key: const Key('parent-pin-cancel'),
                      onPressed: onCancel,
                      child: const Text('Back'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One selectable profile cell: avatar, name, remaining time and the
/// "Enforce time" toggle, with a visible border while focused (D-pad) and
/// D-pad/tap activation.
///
/// Editing: a long-press (touch, or holding Select/Enter on the D-pad for
/// at least [_longPressDuration]) opens the profile's editor instead of
/// selecting — hence activation happens on key-up, so a held key can be
/// told apart from a short press.
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({
    super.key,
    required this.profile,
    required this.remainingSeconds,
    required this.enforced,
    required this.autofocus,
    required this.onSelected,
    required this.onToggle,
    required this.onEdit,
  });

  final Profile profile;
  final int? remainingSeconds;

  /// Whether this profile's session is the one currently enforced.
  final bool enforced;

  final bool autofocus;
  final VoidCallback onSelected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

/// Shared Select/Enter handling for the picker's grid cells: a SHORT press
/// activates on key-up; holding for [duration] fires [onHold] instead (an
/// edit request), and the eventual key-up is then dead. With no [onHold]
/// a hold is simply dead (nothing on release either).
class _SelectPressHandler {
  _SelectPressHandler({required this.onPress, this.onHold});

  /// How long Select/Enter must be held to count as a hold (matching the
  /// touch long-press timeout).
  static const duration = Duration(milliseconds: 500);

  final VoidCallback onPress;
  final VoidCallback? onHold;

  Timer? _timer;
  bool _holdFired = false;

  KeyEventResult handle(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.select && key != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      _holdFired = false;
      _timer?.cancel();
      _timer = Timer(duration, () {
        _holdFired = true;
        onHold?.call();
      });
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // A held remote key repeats; the timer already covers the hold.
      return KeyEventResult.handled;
    }
    // Key-up: a short press activates; a hold already fired (or is dead).
    _timer?.cancel();
    final press = !_holdFired;
    _holdFired = false;
    if (press) onPress();
    return KeyEventResult.handled;
  }

  void dispose() => _timer?.cancel();
}

class _ProfileCardState extends State<_ProfileCard> {
  // The closures read `widget.` at call time, so a rebuilt card (new
  // callbacks) is always honored.
  late final _press = _SelectPressHandler(
    onPress: () => widget.onSelected(),
    onHold: () => widget.onEdit(),
  );

  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'profile-card-${widget.profile.id}',
    onKeyEvent: _press.handle,
  );

  @override
  void dispose() {
    _press.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, _) {
          final focused = _focusNode.hasFocus;
          return Container(
            key: Key('profile-card-border-${profile.id}'),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: focused
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                width: 4,
              ),
            ),
            child: InkWell(
              onTap: widget.onSelected,
              onLongPress: widget.onEdit,
              // Focus is owned by the FocusableActionDetector above; the
              // InkWell's internal focus node must not become a second
              // traversal stop per cell (same rule as the PIN pad).
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(12),
              // Scale the whole cell down to fit small surfaces (a TV is
              // huge, but tests and phone-shaped windows are not): the card
              // content is intrinsic and FittedBox keeps it from overflowing.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      child: Text(
                        profile.avatar.isEmpty
                            ? '?'
                            : profile.avatar[0].toUpperCase(),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (widget.remainingSeconds != null)
                      Text(_formatRemaining(widget.remainingSeconds!)),
                    const SizedBox(height: 8),
                    // The core interaction: the switch owns enforcement. Its
                    // subtree is kept out of focus traversal (the card
                    // itself is the single D-pad stop per cell) — a tap
                    // still flips it.
                    Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Enforce time',
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(width: 8),
                          Switch(
                            key: Key('profile-toggle-${profile.id}'),
                            value: widget.enforced,
                            onChanged: widget.onToggle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _formatRemaining(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return 'Remaining ${minutes}m ${secs.toString().padLeft(2, '0')}s';
  }
}

/// The trailing "Add profile" cell: D-pad-focusable and tappable, opens the
/// (PIN-gated) create form. Shown last in the grid, and alone when the
/// picker is empty.
class _AddProfileCard extends StatefulWidget {
  const _AddProfileCard({
    super.key,
    required this.autofocus,
    required this.onSelected,
  });

  /// Whether the card takes focus on first build (the only focusable thing
  /// on an otherwise-empty picker).
  final bool autofocus;
  final VoidCallback onSelected;

  @override
  State<_AddProfileCard> createState() => _AddProfileCardState();
}

class _AddProfileCardState extends State<_AddProfileCard> {
  // Same key-up activation as the profile cards; there is no hold action,
  // so a held key is simply dead (consistent short/long semantics across
  // the grid). The closures read `widget.` at call time.
  late final _press = _SelectPressHandler(
    onPress: () => widget.onSelected(),
  );

  late final FocusNode _focusNode = FocusNode(
    debugLabel: 'add-profile-card',
    onKeyEvent: _press.handle,
  );

  @override
  void dispose() {
    _press.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      child: ListenableBuilder(
        listenable: _focusNode,
        builder: (context, _) {
          final focused = _focusNode.hasFocus;
          final colorScheme = Theme.of(context).colorScheme;
          return Container(
            key: const Key('add-profile-card-border'),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: focused
                    ? colorScheme.primary
                    : colorScheme.outlineVariant,
                width: 4,
              ),
            ),
            child: InkWell(
              onTap: widget.onSelected,
              // One traversal stop per cell (focus lives on the
              // FocusableActionDetector above).
              canRequestFocus: false,
              borderRadius: BorderRadius.circular(12),
              // Scale the whole cell down to fit small surfaces, exactly like
              // _ProfileCard: the home banner (overlay permission denied) can
              // squeeze the picker on a 540p TV until the grid cells are tiny,
              // and without this the intrinsic Column overflows the cell.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add_alt_1,
                        size: 64, color: colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'Add profile',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

