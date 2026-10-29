// The phone profiles dashboard: one row per child (avatar, name, allowance
// chip, live remaining time), per-row Add-time and Override, an allowance
// editor on long-press, the master-lock switch, and profile creation (the
// FAB — this is the only place new profiles are made; the TV picker only
// selects).
//
// Every mutation is PIN-gated on the TV: the PIN entered here is only
// forwarded to the TV inside the client call, and the server's verdict
// (403 on a wrong PIN) is shown inline by the dialogs, which stay open.

library;

import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';

import '../state/phone_controller.dart';
import '../tv/widgets/last_minute_countdown.dart' show formatSessionSeconds;
import '../widgets/avatar_choices.dart';
import 'widgets/master_lock_switch.dart';
import 'widgets/pin_dialog.dart';

// The avatar set lives in the shared widgets folder (the TV form uses it
// too); re-exported so existing importers of this file keep working.
export '../widgets/avatar_choices.dart' show kAvatarChoices;

/// The parent's view of the TV: builds (and owns, unless injected) a
/// [PhoneController] polling [client].
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({
    super.key,
    required this.client,
    this.controller,
    this.pollInterval = const Duration(seconds: 5),
  });

  /// The TV operations to poll and mutate. Tests inject a fake so no
  /// sockets are opened.
  final EleenOps client;

  /// Optional pre-built controller. When null the screen builds its own
  /// from [client] and disposes it with the screen.
  final PhoneController? controller;

  /// Injectable poll interval (tests use a long one so the periodic timer
  /// never fires mid-test).
  final Duration pollInterval;

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  late final PhoneController _controller =
      widget.controller ?? PhoneController(client: widget.client,
          pollInterval: widget.pollInterval);
  late final bool _ownsController = widget.controller == null;

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// Whether the TV has a parent PIN set (from the latest poll). With none
  /// set every PIN dialog is skipped and the actions run with the empty
  /// pin — the TV accepts any pin while no PIN is provisioned.
  bool get _pinSet => _controller.state?.parentPinSet ?? false;

  Future<void> _addTime(Profile profile) async {
    final pin = await PinDialog.show(
      context,
      title: 'Add time for ${profile.name} — enter parent PIN',
      pinSet: _pinSet,
    );
    if (pin == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PickDialog(
        dialogKey: const Key('add-amounts'),
        title: 'Add how much time for ${profile.name}?',
        values: const [15, 30, 45, 60],
        label: (m) => '$m min',
        keyPrefix: 'add-amount',
        onPick: (minutes) =>
            _controller.addTime(profile.id, minutes * 60, pin),
      ),
    );
  }

  Future<void> _overrideTime(Profile profile) async {
    final pin = await PinDialog.show(
      context,
      title: 'Override time for ${profile.name} — enter parent PIN',
      pinSet: _pinSet,
    );
    if (pin == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PickDialog(
        dialogKey: const Key('override-picker'),
        title: 'Set remaining time for ${profile.name}',
        values: const [0, 5, 10, 15, 20, 30, 45, 60],
        label: (m) => '$m min',
        keyPrefix: 'override-minutes',
        onPick: (minutes) =>
            _controller.overrideTime(profile.id, minutes * 60, pin),
      ),
    );
  }

  Future<void> _editAllowance(Profile profile) async {
    final pin = await PinDialog.show(
      context,
      title: 'Allowance for ${profile.name} — enter parent PIN',
      pinSet: _pinSet,
    );
    if (pin == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PickDialog(
        dialogKey: const Key('allowance-picker'),
        title: 'Daily allowance for ${profile.name}',
        values: AllowanceMinutes.values.map((a) => a.minutes).toList(),
        label: (m) => '$m min',
        keyPrefix: 'allowance',
        onPick: (minutes) => _controller.upsertProfile(
          Profile(
            id: profile.id,
            name: profile.name,
            avatar: profile.avatar,
            allowance: AllowanceMinutes.fromMinutes(minutes)!,
            isParent: profile.isParent,
          ),
          pin,
        ),
      ),
    );
  }

  Future<void> _createProfile() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateProfileDialog(
        pinSet: () => _pinSet,
        onCreate: (profile, pin) => _controller.upsertProfile(profile, pin),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final state = _controller.state;
        return Scaffold(
          appBar: AppBar(title: const Text('Screen time')),
          floatingActionButton: FloatingActionButton(
            key: const Key('add-profile'),
            tooltip: 'Add profile',
            onPressed: _createProfile,
            child: const Icon(Icons.person_add_alt_1),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_controller.offline)
                Container(
                  key: const Key('offline-banner'),
                  color: theme.colorScheme.errorContainer,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off,
                          color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          eleenOfflineCopy,
                          style: TextStyle(
                              color: theme.colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              _overlayPermissionHint(theme, state),
              MasterLockSwitch(controller: _controller),
              Expanded(child: _buildBody(context, state)),
            ],
          ),
        );
      },
    );
  }

  /// Mirrors the TV's SYSTEM_ALERT_WINDOW status (reported over the LAN
  /// sync): while the TV lacks "Display over other apps", its lock cannot
  /// cover other apps, so the parent sees a warning here. Informational
  /// only — the grant itself must be done on the TV (this device cannot
  /// open the TV's system settings).
  Widget _overlayPermissionHint(ThemeData theme, TvState? state) {
    if (state == null || state.overlayPermissionGranted) {
      return const SizedBox.shrink(
          key: Key('tv-overlay-permission-allowed'));
    }
    return Container(
      key: const Key('tv-overlay-permission-denied'),
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The TV can\'t lock other apps yet — on the TV, allow '
              '"Display over other apps" for Eleen (Eleen home → '
              '"Overlays blocked").',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, TvState? state) {
    if (state == null) {
      if (_controller.offline) {
        return const Center(child: Text('Not connected to the TV'));
      }
      if (_controller.error != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_controller.error!),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _controller.refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        if (state.profiles.isEmpty)
          // Fresh install: nothing to show yet — point the parent at the
          // create form instead of an unexplained blank list.
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                const Icon(Icons.child_care, size: 48),
                const SizedBox(height: 12),
                const Text('No profiles yet'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('add-profile-empty'),
                  onPressed: _createProfile,
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Add profile'),
                ),
              ],
            ),
          ),
        for (final profile in state.profiles)
          _buildRow(context, profile, state.masterLockEnabled),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    Profile profile,
    bool masterLockEnabled,
  ) {
    final remaining = _controller.remainingFor(profile.id);
    // Parent rows carry a Parent badge, no remaining-time line and none of
    // the per-row time controls (a parent's session needs none).
    return Opacity(
      key: Key('profile-row-${profile.id}-dim'),
      opacity: masterLockEnabled ? 0.5 : 1.0,
      child: ListTile(
        key: Key('profile-row-${profile.id}'),
        leading: CircleAvatar(
          child: Text(profile.avatar.isEmpty
              ? '?'
              : profile.avatar[0].toUpperCase()),
        ),
        title: Row(
          children: [
            Text(profile.name),
            if (profile.isParent) ...[
              const SizedBox(width: 6),
              // Same lock icon as the TV's Parent badge: "Parent" means
              // PIN-gated, and lock carries that on both devices.
              const Icon(Icons.lock, size: 16),
              const Text(
                'Parent',
                key: Key('parent-row-badge'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (masterLockEnabled) ...[
              const SizedBox(width: 6),
              const Icon(Icons.lock, size: 16),
            ],
          ],
        ),
        subtitle: _subtitle(profile, remaining),
        trailing: profile.isParent
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () => _addTime(profile),
                    child: const Text('Add time'),
                  ),
                  TextButton(
                    onPressed: () => _overrideTime(profile),
                    child: const Text('Override'),
                  ),
                ],
              ),
        onLongPress: () => _editAllowance(profile),
      ),
    );
  }

  /// The row's subtitle: the remaining-time line for children (usage lines
  /// appended below it), and for parents just the usage lines — parents
  /// have no remaining row, so usage is their line. Falls back to the
  /// plain "Parent profile" label when no usage is known (older server or
  /// nothing used yet).
  Widget _subtitle(Profile profile, int remaining) {
    final lines = _usageLines(profile);
    if (profile.isParent) {
      if (lines.isEmpty) return const Text('Parent profile');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Allowance ${profile.allowance.minutes} min · '
          '${formatSessionSeconds(remaining)} left',
        ),
        ...lines,
      ],
    );
  }

  /// The usage lines (v1.1 D) for [profile]'s row: "Used today: N min"
  /// (when anything was used today) and "Yesterday: N min" (when yesterday
  /// appears in the history). Empty when the server carries no usage at
  /// all (older server) — tolerated by simply rendering nothing.
  List<Text> _usageLines(Profile profile) {
    final usage = _controller.state?.usageByProfile[profile.id];
    if (usage == null) return const [];
    final lines = <Text>[];
    if (usage.todaySeconds > 0) {
      lines.add(Text(
        'Used today: ${(usage.todaySeconds / 60).round()} min',
        key: Key('usage-today-${profile.id}'),
      ));
    }
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    for (final day in usage.history) {
      if (day.date.year == yesterday.year &&
          day.date.month == yesterday.month &&
          day.date.day == yesterday.day &&
          day.seconds > 0) {
        lines.add(Text(
          'Yesterday: ${(day.seconds / 60).round()} min',
          key: Key('usage-yesterday-${profile.id}'),
        ));
        break;
      }
    }
    return lines;
  }
}

/// The profile-creation form: name, avatar, a daily allowance, then a PIN
/// confirmation. Every profile created here is a child profile (the app
/// only enforces screen time now; the wire model keeps `isParent` for
/// compatibility). Submits the create path (`upsertProfile` with an empty
/// id — the server assigns the id and the controller refreshes), so this is
/// provisioning, not local state.
///
/// The PIN step reuses [PinDialog.run]: the create call runs inside it, so
/// a wrong PIN (403) shows inline there and nothing is created.
class _CreateProfileDialog extends StatefulWidget {
  const _CreateProfileDialog({
    required this.onCreate,
    required this.pinSet,
  });

  final Future<void> Function(Profile profile, String pin) onCreate;

  /// Read at submit time: whether the TV has a parent PIN set. With none
  /// set the PIN confirmation step is skipped entirely.
  final bool Function() pinSet;

  @override
  State<_CreateProfileDialog> createState() => _CreateProfileDialogState();
}

class _CreateProfileDialogState extends State<_CreateProfileDialog> {
  final TextEditingController _name = TextEditingController();
  String _avatar = kAvatarChoices.first;
  AllowanceMinutes _allowance = AllowanceMinutes.thirty;
  String? _error;

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final ok = await PinDialog.run(
      context,
      title: 'Create $name — enter parent PIN',
      pinSet: widget.pinSet(),
      onSubmit: (pin) => widget.onCreate(
        Profile(
          id: '',
          name: name,
          avatar: _avatar,
          allowance: _allowance,
          isParent: false,
        ),
        pin,
      ),
    );
    if (!mounted) return;
    if (ok) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('create-profile'),
      title: const Text('Add profile'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('create-name'),
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Child name'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final (i, avatar) in kAvatarChoices.indexed)
                  ChoiceChip(
                    key: Key('avatar-choice-$i'),
                    label: Text(avatar),
                    selected: _avatar == avatar,
                    onSelected: (_) => setState(() => _avatar = avatar),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final minutes in AllowanceMinutes.values)
                  ChoiceChip(
                    key: Key('create-allowance-${minutes.minutes}'),
                    label: Text('${minutes.minutes} min'),
                    selected: _allowance == minutes,
                    onSelected: (_) => setState(() => _allowance = minutes),
                  ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                key: const Key('create-error'),
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('create-submit'),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

/// A picker of numeric options (minutes) that runs a PIN-gated action on
/// tap: closes on success, shows the server's error inline and stays open
/// on failure.
class _PickDialog extends StatefulWidget {
  const _PickDialog({
    required this.title,
    required this.values,
    required this.label,
    required this.keyPrefix,
    required this.onPick,
    this.dialogKey,
  });

  final String title;
  final List<int> values;
  final String Function(int value) label;
  final String keyPrefix;
  final Future<void> Function(int value) onPick;
  final Key? dialogKey;

  @override
  State<_PickDialog> createState() => _PickDialogState();
}

class _PickDialogState extends State<_PickDialog> {
  int? _picking;
  String? _error;

  Future<void> _pick(int value) async {
    if (_picking != null) return;
    setState(() {
      _picking = value;
      _error = null;
    });
    try {
      await widget.onPick(value);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _picking = null;
        _error = describeEleenError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: widget.dialogKey,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in widget.values)
                FilledButton.tonal(
                  key: Key('${widget.keyPrefix}-$value'),
                  onPressed: _picking == null
                      ? () => _pick(value)
                      : null,
                  child: Text(widget.label(value)),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              key: const Key('pick-error'),
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _picking == null
              ? () => Navigator.of(context).pop()
              : null,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
