// Parent PIN dialog for the phone dashboard.
//
// The phone never verifies a PIN: whatever is typed here travels to the TV
// inside the client call (addTime / overrideTime / setMasterLock /
// upsertProfile), and a wrong PIN comes back as the server's 403. The
// dialog therefore runs the action itself ([PinDialog.run] or an injected
// [PinDialog.onSubmit]), shows the server's failure inline and stays open.

import 'dart:io';

import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The offline copy, shared by the dashboard banner and every dialog error.
const String eleenOfflineCopy =
    'TV offline — check both devices are on the same Wi-Fi';

/// Maps a failure from an Eleen client call to parent-facing copy. A 403 is
/// the server rejecting the PIN; HttpException-family errors escaping the
/// client are treated as offline (client.dart only maps SocketException).
String describeEleenError(Object error) => switch (error) {
      EleenApiError(status: 403) => 'Wrong PIN',
      EleenApiError(status: 401) => 'Pairing expired — pair with the TV again',
      EleenApiError(:final status) => 'TV error (HTTP $status)',
      EleenOffline() => eleenOfflineCopy,
      SocketException() => eleenOfflineCopy,
      HttpException() => eleenOfflineCopy,
      _ => 'Something went wrong — try again',
    };

/// Modal parent-PIN entry.
///
/// Two modes:
/// - `PinDialog.show` — collect a PIN and pop with it (the caller then
///   walks a second step, e.g. a minute picker).
/// - `PinDialog.run` — collect a PIN and run [PinDialog.onSubmit] with it
///   directly; on success the dialog closes, on failure the error shows
///   inline and the dialog stays up.
///
/// The parent PIN is optional: callers pass [PinDialog.show]/`run` a
/// `pinSet` flag (from the TV's `parentPinSet` state). With no PIN set the
/// dialog never appears — the action proceeds straight away with the empty
/// pin (the TV accepts any pin while none is set); a `run` failure still
/// surfaces, as a snackbar.
class PinDialog extends StatefulWidget {
  const PinDialog({super.key, required this.title, this.onSubmit});

  final String title;

  /// When set, the entered PIN is passed to this (typically a controller
  /// call that forwards it to the TV) instead of popping with the value.
  final Future<void> Function(String pin)? onSubmit;

  /// Collects a PIN and pops with it; null when dismissed. With
  /// [pinSet] false the dialog never opens and the empty pin is returned.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    bool pinSet = true,
  }) async {
    if (!pinSet) return '';
    return showDialog<String>(
      context: context,
      builder: (_) => PinDialog(title: title),
    );
  }

  /// Collects a PIN and runs [onSubmit] with it. Returns true when the
  /// action succeeded (dialog closed) and false when it was cancelled or
  /// failed. With [pinSet] false the dialog never opens: [onSubmit] runs
  /// with the empty pin and a failure surfaces as a snackbar.
  static Future<bool> run(
    BuildContext context, {
    required String title,
    required Future<void> Function(String pin) onSubmit,
    bool pinSet = true,
  }) async {
    if (!pinSet) {
      try {
        await onSubmit('');
        return true;
      } on Object catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(describeEleenError(e))),
          );
        }
        return false;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PinDialog(title: title, onSubmit: onSubmit),
    );
    return ok ?? false;
  }

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final TextEditingController _pin = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The Confirm button's node: the moment the 4th digit lands, focus
  /// jumps here so Enter/Select submits — no extra tab/arrow press.
  final FocusNode _submitFocus = FocusNode(debugLabel: 'pin-submit');

  @override
  void initState() {
    super.initState();
    _pin.addListener(_onPinChanged);
  }

  void _onPinChanged() {
    if (_pin.text.length == 4) _submitFocus.requestFocus();
  }

  @override
  void dispose() {
    _pin.removeListener(_onPinChanged);
    _submitFocus.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pin.text;
    if (pin.isEmpty) {
      setState(() => _error = 'Enter the parent PIN');
      return;
    }
    // The PIN is exactly 4 digits: reject anything shorter before it reaches
    // the TV (a hardware keyboard, paste or autofill could bypass the pad).
    if (pin.length != 4) {
      setState(() => _error = 'Use at least 4 digits');
      return;
    }
    final action = widget.onSubmit;
    if (action == null) {
      Navigator.of(context).pop(pin);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(pin);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      // The server's verdict (403 = wrong PIN) — show it and stay.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeEleenError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('pin-field'),
            controller: _pin,
            obscureText: true,
            keyboardType: TextInputType.number,
            autofocus: true,
            enabled: !_busy,
            // Digits only, exactly 4 (BUG-9): a hardware keyboard, paste or
            // autofill must not submit letters or an arbitrary length.
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: const InputDecoration(labelText: 'Parent PIN'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              key: const Key('pin-error'),
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const Key('pin-cancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('pin-submit'),
          focusNode: _submitFocus,
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Confirm'),
        ),
      ],
    );
  }
}
