// The TV profile form: create a profile, or edit an existing one.
//
// Reached only through the picker's parent-PIN gate (a kid must not
// self-grant time or create a parent profile). The form itself holds no PIN
// logic — the gate in [ProfilePicker] has already admitted the user by the
// time this screen is pushed.
//
// D-pad + touch navigable end to end: every control is focusable and
// activates on Select/Enter or tap. All sizes derive from the form's own
// viewport via a [LayoutBuilder] — never fixed pixels — so it fills any TV
// screen shape.
//
// Persistence goes through the same [EngineCoordinator] paths the HTTP
// routes use (`createProfile` / `patchProfile`), so the phone sees the
// change on its next poll. Editing rewrites only the profile row: the
// session (remaining time / active flag) is untouched.

import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';

import '../state/tv_controller.dart';
import '../widgets/avatar_choices.dart';
import 'tv_theme.dart';

/// Full-screen form for creating a profile ([existing] == null) or editing
/// one. Fields: name (system IME via a plain [TextField]), avatar from the
/// shared set and daily-allowance chips 5/15/30/45/60. Every profile is a
/// child profile now (the TV only manages enforcement); save persists
/// through the coordinator, Cancel pops without writing.
class ProfileForm extends StatefulWidget {
  const ProfileForm({super.key, required this.controller, this.existing});

  final TvController controller;

  /// Non-null: edit this profile instead of creating a new one.
  final Profile? existing;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<ProfileForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');

  /// The name field's node, exposed with NO autofocus: on a real TV an
  /// autofocus here would summon the system IME the moment the form opens
  /// and capture D-pad events. The initial focus goes to the first avatar
  /// chip instead; the user moves to the name field deliberately.
  final FocusNode _nameFocus = FocusNode(debugLabel: 'profile-form-name');

  /// The first avatar chip's node: the deliberate focus target after the
  /// name field's Done key (generic nextFocus() would land back on the name
  /// field — the first focusable in the scope — trapping the IME).
  final FocusNode _firstAvatarFocus =
      FocusNode(debugLabel: 'profile-form-first-avatar');

  late String _avatar =
      widget.existing?.avatar ?? kAvatarChoices.first;
  late AllowanceMinutes _allowance =
      widget.existing?.allowance ?? AllowanceMinutes.thirty;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Land the initial D-pad focus on the first avatar chip, never the name
    // field (an autofocus there would summon the IME on a TV). The route
    // transition can swallow a widget-level `autofocus`, so request it
    // explicitly once the form's scope is up — mirrors the name field's
    // Done-key path, which targets the same node.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_firstAvatarFocus.hasFocus) {
        _firstAvatarFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    _firstAvatarFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.existing;
      if (existing == null) {
        await widget.controller.coordinator.createProfile(
          name: name,
          avatar: _avatar,
          allowance: _allowance,
          // Every profile the TV creates is a child profile: the picker
          // only enforces screen time, it no longer manages parent
          // profiles (the wire model keeps isParent for the phone).
          isParent: false,
        );
      } else {
        await widget.controller.coordinator.patchProfile(
          existing.id,
          name: name,
          avatar: _avatar,
          allowance: _allowance,
          isParent: false,
        );
      }
      await widget.controller.refresh();
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the profile: $error';
      });
      // Spec: a save failure surfaces a toast (not only the inline error),
      // and the form stays open with its values intact.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the profile: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // All sizes derive from the form's own viewport, never fixed pixels.
    return Scaffold(
      key: const Key('profile-form'),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          // Widget order == reading order: name, avatar, allowance,
          // actions — the D-pad traversal follows it.
          return FocusTraversalGroup(
            policy: WidgetOrderTraversalPolicy(),
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: h),
                child: Padding(
                  padding: EdgeInsets.all(w * 0.04),
                  // The panel stays in the left half on wide TVs: Gboard on
                  // Android TV floats center-bottom and never reports
                  // insets, so full-width actions would sit under it.
                  // Narrow surfaces (phones/small windows) keep full width —
                  // narrowing there would wrap the chips and bury actions.
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: w >= 1200 ? w * 0.5 : double.infinity),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text(
                        widget.existing == null
                            ? 'Add profile'
                            : 'Edit ${widget.existing!.name}',
                        style: TextStyle(
                          fontSize: TvType.title(w),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: TvSpace.md(h)),
                      TextField(
                        key: const Key('profile-form-name'),
                        controller: _name,
                        focusNode: _nameFocus,
                        textCapitalization: TextCapitalization.words,
                        // Done/Enter must release the field: on TV a focused
                        // editable re-summons the IME on every D-pad key,
                        // trapping the user in a show/hide keyboard loop.
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          _nameFocus.unfocus();
                          // Explicit target: nextFocus() from the scope would
                          // land back on the name field (first focusable in
                          // the traversal group), re-summoning the IME.
                          _firstAvatarFocus.requestFocus();
                        },
                        style: TextStyle(fontSize: TvType.button(w)),
                        decoration: InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(fontSize: TvType.body(w)),
                        ),
                      ),
                      SizedBox(height: TvSpace.md(h)),
                      Text('Avatar',
                          style: TextStyle(
                              fontSize: TvType.body(w),
                              fontWeight: FontWeight.w600)),
                      Wrap(
                        spacing: w * 0.01,
                        children: [
                          for (final (i, avatar) in kAvatarChoices.indexed)
                            ChoiceChip(
                              key: Key('profile-form-avatar-$i'),
                              // The form's initial D-pad focus lands here
                              // (never on the name field: that would pop
                              // the IME over the form on a real TV).
                              autofocus: i == 0,
                              focusNode:
                                  i == 0 ? _firstAvatarFocus : null,
                              label: Text(avatar,
                                  style: TextStyle(fontSize: TvType.body(w))),
                              selected: _avatar == avatar,
                              onSelected: (_) =>
                                  setState(() => _avatar = avatar),
                            ),
                        ],
                      ),
                      SizedBox(height: TvSpace.sm(h)),
                      Text('Daily allowance',
                          style: TextStyle(
                              fontSize: TvType.body(w),
                              fontWeight: FontWeight.w600)),
                      Wrap(
                        spacing: w * 0.01,
                        runSpacing: w * 0.01,
                        children: [
                          for (final minutes in AllowanceMinutes.values)
                            ChoiceChip(
                              key: Key(
                                  'profile-form-allowance-${minutes.minutes}'),
                              label: Text('${minutes.minutes} min',
                                  style:
                                      TextStyle(fontSize: TvType.body(w))),
                              selected: _allowance == minutes,
                              onSelected: (_) => setState(
                                  () => _allowance = minutes),
                            ),
                        ],
                      ),
                      if (_error != null) ...[
                        SizedBox(height: TvSpace.sm(h)),
                        Text(
                          key: const Key('profile-form-error'),
                          _error!,
                          style: TextStyle(
                            color: TvColors.error,
                            fontSize: TvType.body(w),
                          ),
                        ),
                      ],
                      SizedBox(height: TvSpace.lg(h)),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            key: const Key('profile-form-cancel'),
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          SizedBox(width: w * 0.02),
                          FilledButton(
                            key: const Key('profile-form-save'),
                            onPressed: _saving ? null : _save,
                            child: Text(
                                widget.existing == null
                                    ? 'Create'
                                    : 'Save',
                                style: TextStyle(fontSize: TvType.body(w))),
                          ),
                        ],
                      ),
                        ],
                      ),
                    ),
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
