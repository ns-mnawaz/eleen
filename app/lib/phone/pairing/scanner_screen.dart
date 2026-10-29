/// Phone-side pairing: scans the TV's QR (in-app, `mobile_scanner`) and
/// falls back to pasting the pairing code when the camera is unavailable.
///
/// Flow on a detected `eleen://pair?host=..&port=..&nonce=..` payload:
/// [PairingCodec.parse] -> [EleenClient.pair] with the extracted nonce ->
/// [PairedStore.save] -> the optional [ScannerScreen.provisionPin] step ->
/// pop with the `(base, token)` result so the caller can continue to the
/// profiles screen.
///
/// Failure modes get explicit copy (see [_PairCopy]): a bad payload, a
/// stale nonce, and an unreachable TV each tell the parent what to do next.
/// The manual code field is always visible, so a missing camera or a blocked
/// platform channel degrades to paste-entry instead of a dead end.
library;

import 'dart:io';

import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'paired_store.dart';

/// Performs the pairing exchange against [base] with the single-use
/// [nonce]; returns the issued bearer token. Injectable so tests never open
/// a socket.
typedef PairFn = Future<String> Function(Uri base, String nonce);

/// Production pairing: a fresh client pointed at the TV.
Future<String> defaultPair(Uri base, String nonce) =>
    EleenClient(base: base).pair(nonce);

/// The full pairing screen: live camera preview on top, manual code entry
/// below. Tests inject [scannerBuilder] and a fake [pair].
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({
    super.key,
    required this.store,
    this.pair = defaultPair,
    this.scannerBuilder,
    this.provisionPin,
  });

  /// Where the issued token + TV base URI are persisted.
  final PairedStore store;

  /// The pairing exchange. Defaults to the real [EleenClient].
  final PairFn pair;

  /// Builds the live scanner surface. Defaults to a `MobileScanner` camera
  /// preview; tests replace it so no camera is needed. Whatever it shows,
  /// detected values enter via [ScannerScreenState.handleScannedValue].
  final WidgetBuilder? scannerBuilder;

  /// Optional post-pair step, run right after the token is saved and
  /// BEFORE the screen pops, with the fresh `(base, token)`. This is where
  /// the parent PIN gets provisioned on a fresh install (see PhoneHome):
  /// running it inside the pairing exchange keeps it best-effort — a
  /// failure is logged and the pairing still succeeds.
  final Future<void> Function(Uri base, String token)? provisionPin;

  @override
  State<ScannerScreen> createState() => ScannerScreenState();
}

class ScannerScreenState extends State<ScannerScreen> {
  String? _error;
  bool _busy = false;
  final TextEditingController _manualController = TextEditingController();

  /// Entry point for every scanned value (QR frames, injected test
  /// payloads, nothing else). Ignored while a pair is in flight — camera
  /// frames repeat and the nonce is single-use.
  void handleScannedValue(String value) {
    if (_busy) return;
    final parsed = PairingCodec.parse(value);
    if (parsed == null) {
      setState(() => _error = _PairCopy.badPayload);
      return;
    }
    final base = Uri(scheme: 'http', host: parsed.host, port: parsed.port);
    _pair(base, parsed.nonce);
  }

  Future<void> _pair(Uri base, String nonce) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final token = await widget.pair(base, nonce);
      try {
        await widget.store.save(base, token);
      } catch (e) {
        // A persistence failure (platform channel down, corrupt prefs) must
        // surface as UI feedback, not an unhandled async error. The screen
        // stays up; the parent can retry with a fresh code.
        debugPrint('eleen pairing save failed: $e');
        _showError(_PairCopy.saveFailed);
        return;
      }
      final provision = widget.provisionPin;
      if (provision != null) {
        try {
          await provision(base, token);
        } on Object catch (e) {
          // Provisioning must never strand a successful pairing: whatever
          // it throws, the parent still lands on the paired home.
          debugPrint('eleen post-pair provisioning failed: $e');
        }
      }
      if (!mounted) return;
      // Positional record, matching the documented PairedStore.load shape.
      Navigator.pop(context, (base, token));
    } on EleenApiError catch (e) {
      _showError(e.status == 401
          ? _PairCopy.expired
          : 'Pairing failed (HTTP ${e.status})');
    } on EleenOffline {
      _showError(_PairCopy.offline);
    } on SocketException {
      // client.dart maps SocketException -> EleenOffline, so this is only
      // reachable for errors thrown outside _send; same UI either way.
      _showError(_PairCopy.offline);
    } on HttpException {
      // Task 6 finding: client.dart does NOT map HttpException-family
      // errors to EleenOffline, so they would otherwise escape here raw.
      // The screen still shows the offline copy rather than a crash.
      _showError(_PairCopy.offline);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submitManual() {
    if (_busy) return;
    final text = _manualController.text.trim();
    final parsed = PairingCodec.parse(text);
    if (parsed != null) {
      final base = Uri(scheme: 'http', host: parsed.host, port: parsed.port);
      _pair(base, parsed.nonce);
      return;
    }
    // A bare address (`192.168.1.50:8477`) has no nonce — pairing needs the
    // one-time code, so say so instead of a guaranteed 401.
    if (RegExp(r'^[\w.\-]+:\d{1,5}$').hasMatch(text)) {
      _showError(_PairCopy.addressOnly);
      return;
    }
    _showError(_PairCopy.badPayload);
  }

  void _showError(String message) {
    // Errors can land after await points while the user has already backed
    // out of the screen (back is not disabled mid-pair) — never setState on
    // a disposed state.
    if (!mounted) return;
    setState(() => _error = message);
    debugPrint('eleen pairing error: $message');
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pair with TV')),
      body: Column(
        children: [
          Expanded(child: _buildScanner(context)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_error!,
                        style: Theme.of(context).textTheme.bodyLarge),
                  ),
                ],
              ),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const Key('manual-payload'),
                  controller: _manualController,
                  enabled: !_busy,
                  decoration: const InputDecoration(
                    labelText: 'Or enter the TV pairing code',
                    hintText: 'eleen://pair?host=…&port=…&nonce=…',
                  ),
                  onSubmitted: (_) => _submitManual(),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('manual-submit'),
                  onPressed: _busy ? null : _submitManual,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Pair'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanner(BuildContext context) {
    final builder = widget.scannerBuilder;
    if (builder != null) return builder(context);
    // Live camera preview, in-app only. If the platform reports no camera
    // (or the channel errors), degrade to the manual field — never a dead
    // end.
    return MobileScanner(
      onDetect: (capture) {
        for (final barcode in capture.barcodes) {
          final value = barcode.rawValue;
          if (value != null && value.isNotEmpty) {
            handleScannedValue(value);
            return;
          }
        }
      },
      errorBuilder: (context, error) => const _CameraUnavailable(),
    );
  }
}

class _CameraUnavailable extends StatelessWidget {
  const _CameraUnavailable();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 48),
          const SizedBox(height: 12),
          Text('Camera unavailable — enter the pairing code below',
              style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}

/// The pairing error copy, in one place so tests and UI agree.
abstract final class _PairCopy {
  static const badPayload = 'Not a valid Eleen pairing code';
  static const expired = 'Pairing code expired — ask parent to show a new code';
  static const offline = 'TV offline — check both devices are on the same Wi-Fi';
  static const addressOnly =
      'The address alone cannot pair — you need the one-time code: scan the '
      'QR, or paste the full eleen://pair code it encodes';
  static const saveFailed =
      'Paired with the TV, but the token could not be saved on this device — '
      'try again';
}
