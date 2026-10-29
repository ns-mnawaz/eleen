// Post-pair parent-PIN provisioning dialog.
//
// Shown by PhoneHome right after a fresh pairing when the TV reports no
// parent PIN yet — the pairing phone is by definition the parent device, so
// this is the moment the PIN gets provisioned. Two fields (enter + confirm),
// at least 4 digits; the PIN is sent to the TV through [onSubmit]
// (`EleenClient.setPin` -> `PUT /api/pin`). A failure (offline, TV error)
// shows inline and the dialog stays open, mirroring [PinDialog].
//
// The PIN is optional: "Skip for now" (or the field-filled submit) closes
// the dialog and the pairing completes either way — the parent can set or
// change the PIN later from the TV's settings row. Back-press is not the
// skip path (a stray back must not silently skip provisioning); the button
// is the one explicit way past this step.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pin_dialog.dart';

/// Modal "set a parent PIN" dialog with enter + confirm fields.
class SetPinDialog extends StatefulWidget {
  const SetPinDialog({super.key, required this.onSubmit});

  /// Runs the provisioning call with the confirmed PIN. On success the
  /// dialog closes; on failure the error shows inline and it stays up.
  final Future<void> Function(String pin) onSubmit;

  /// Shows the dialog. Returns true when the PIN was set (dialog closed)
  /// and false when it was cancelled or failed.
  static Future<bool> show(
    BuildContext context, {
    required Future<void> Function(String pin) onSubmit,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SetPinDialog(onSubmit: onSubmit),
    );
    return ok ?? false;
  }

  @override
  State<SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends State<SetPinDialog> {
  final TextEditingController _pin = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  /// Focus chain as each field completes its 4 digits: PIN -> confirm ->
  /// Save PIN (Enter/Select then submits — no extra tab press).
  final FocusNode _confirmFocus = FocusNode(debugLabel: 'setpin-confirm');
  final FocusNode _submitFocus = FocusNode(debugLabel: 'setpin-submit');

  @override
  void initState() {
    super.initState();
    _pin.addListener(() {
      if (_pin.text.length == 4) _confirmFocus.requestFocus();
    });
    _confirm.addListener(() {
      if (_confirm.text.length == 4) _submitFocus.requestFocus();
    });
  }

  Future<void> _submit() async {
    final pin = _pin.text;
    // Exactly 4 digits (BUG-9): shorter is rejected here, longer is capped
    // by the field's input formatter.
    if (pin.length != 4) {
      setState(() => _error = 'Use at least 4 digits');
      return;
    }
    if (_confirm.text != pin) {
      setState(() => _error = 'PINs do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeEleenError(e);
      });
    }
  }

  @override
  void dispose() {
    _confirmFocus.dispose();
    _submitFocus.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Provisioning is the whole point of the post-pair step; a stray back
      // press must not silently skip it. Cancel is explicit.
      canPop: !_busy ? false : true,
      child: AlertDialog(
        title: const Text('Set a parent PIN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose the PIN that unlocks this TV — you will need it for '
              'every parent action.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('setpin-field'),
              controller: _pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofocus: true,
              enabled: !_busy,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(labelText: 'New PIN (4 digits)'),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('setpin-confirm'),
              controller: _confirm,
              focusNode: _confirmFocus,
              obscureText: true,
              keyboardType: TextInputType.number,
              enabled: !_busy,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(labelText: 'Confirm PIN'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                key: const Key('setpin-error'),
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            key: const Key('setpin-cancel'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Skip for now'),
          ),
          FilledButton(
            key: const Key('setpin-submit'),
            focusNode: _submitFocus,
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save PIN'),
          ),
        ],
      ),
    );
  }
}
