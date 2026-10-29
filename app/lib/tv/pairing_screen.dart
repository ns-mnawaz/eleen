// The TV pairing screen: a QR code the parent phone app scans to pair with
// this TV.
//
// The QR encodes `eleen://pair?host=..&port=..&nonce=..` (see
// [PairingCodec]). The host comes from network-interface discovery (the LAN
// server binds anyIPv4, so the TV's own address must be looked up), the port
// from the running [EleenServer], and the nonce is generated on open,
// registered single-use with the server, and regenerated after a successful
// pair.
//
// As a fallback discovery path, the TV also advertises itself on the local
// network via mDNS (`_eleen._tcp`, name "Eleen-TV"); a failed registration
// never breaks the screen — the QR is the primary path.

import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/tv_controller.dart';

/// Resolves the address the phone app will use to reach this TV: the first
/// non-loopback IPv4 address of any network interface. Returns null (or
/// throws) when no such address exists — the screen then shows a clear
/// error state instead of a QR with a blank host.
Future<String?> defaultResolveHost() async {
  final interfaces = await NetworkInterface.list();
  for (final interface in interfaces) {
    for (final address in interface.addresses) {
      if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
        return address.address;
      }
    }
  }
  return null;
}

/// Full-screen pairing flow. Injectables ([resolveHost], [generateNonce],
/// [mdnsStart], [mdnsStop]) let widget tests feed a fixed address, a
/// deterministic nonce, and never touch the bonsoir platform channels.
class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    required this.controller,
    this.resolveHost = defaultResolveHost,
    this.generateNonce = PairingCodec.newNonce,
    this.mdnsStart,
    this.mdnsStop,
    this.pollInterval = const Duration(seconds: 1),
  });

  final TvController controller;

  /// Resolves the TV's LAN address for the QR payload.
  final Future<String?> Function() resolveHost;

  /// Generates the single-use pairing nonce (a fresh one per open, and
  /// again after a successful pair).
  final String Function() generateNonce;

  /// Starts the mDNS broadcast for [service]. Defaults to a bonsoir
  /// [BonsoirBroadcast]; failures are caught and logged.
  final Future<void> Function(BonsoirService service)? mdnsStart;

  /// Stops the mDNS broadcast started by [mdnsStart].
  final Future<void> Function()? mdnsStop;

  /// How often the screen polls the settings table for the pairing-success
  /// signal (the server stores the issued token there). Injectable so tests
  /// can drive it deterministically.
  final Duration pollInterval;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  /// The screen's phases: resolving the host, showing the QR (or the error
  /// state when no host was found), and the post-pair confirmation.
  static const _errorText = 'Could not determine TV address — check Wi-Fi';

  String? _host;
  bool _resolving = true;
  bool _complete = false;
  String _nonce = '';
  String? _initialToken;
  Timer? _pollTimer;
  BonsoirBroadcast? _broadcast;

  @override
  void initState() {
    super.initState();
    _nonce = widget.generateNonce();
    widget.controller.registerPairingNonce(_nonce);
    _pollTimer = Timer.periodic(widget.pollInterval, (_) {
      unawaited(_checkPaired());
    });
    unawaited(_init());
  }

  /// Resolves the TV address and starts the mDNS broadcast. mDNS needs only
  /// the port, so it registers immediately on entering the screen — its
  /// failure is logged and otherwise ignored (fallback discovery path).
  Future<void> _init() async {
    // Pairing-success baseline: the token stored before this open. A pair
    // (or re-pair, which rotates the token) always changes it.
    _initialToken = (await widget.controller.db.getSettings()).token;

    final service = BonsoirService(
      name: 'Eleen-TV',
      type: '_eleen._tcp',
      port: widget.controller.serverPort ?? TvController.defaultServerPort,
    );
    unawaited(_registerMdns(service));

    String? host;
    try {
      host = await widget.resolveHost();
    } catch (error) {
      debugPrint('Eleen: could not resolve TV address: $error');
      host = null;
    }
    if (!mounted) return;
    setState(() {
      _host = host;
      _resolving = false;
    });
  }

  Future<void> _registerMdns(BonsoirService service) async {
    try {
      if (widget.mdnsStart != null) {
        await widget.mdnsStart!(service);
      } else {
        final broadcast = BonsoirBroadcast(service: service);
        await broadcast.initialize();
        await broadcast.start();
        _broadcast = broadcast;
      }
    } catch (error) {
      // mDNS is only a fallback discovery path; the QR keeps working.
      debugPrint('Eleen: mDNS registration failed (QR still available): $error');
    }
  }

  Future<void> _unregisterMdns() async {
    final broadcast = _broadcast;
    _broadcast = null;
    try {
      if (widget.mdnsStop != null) {
        await widget.mdnsStop!();
      } else {
        await broadcast?.stop();
      }
    } catch (error) {
      debugPrint('Eleen: mDNS unregister failed: $error');
    }
  }

  /// Pairing-success signal: the server's `POST /api/pair` stores the issued
  /// token in the settings table, so a token other than the open-time
  /// baseline means the phone just paired. On success the screen shows the
  /// confirmation and immediately generates + registers a fresh nonce for
  /// any subsequent display (nonces are single-use).
  Future<void> _checkPaired() async {
    if (_complete || !mounted) return;
    final settings = await widget.controller.db.getSettings();
    if (_complete || !mounted || settings.token == _initialToken) return;
    setState(() {
      _complete = true;
      _nonce = widget.generateNonce();
      widget.controller.registerPairingNonce(_nonce);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    unawaited(_unregisterMdns());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // All sizes proportional to the screen, never fixed pixels.
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_complete) ...[
                Icon(Icons.check_circle,
                    size: shortestSide * 0.15, color: Colors.green),
                SizedBox(height: shortestSide * 0.03),
                Text('Pairing complete ✓',
                    style: Theme.of(context).textTheme.headlineMedium),
              ] else ...[
                Text('Pair with the parent app',
                    style: Theme.of(context).textTheme.headlineLarge),
                SizedBox(height: shortestSide * 0.03),
                if (_resolving)
                  const CircularProgressIndicator()
                else if (_host == null)
                  const Text(_errorText)
                else
                  QrImageView(
                    // The key carries the payload so tests can assert the
                    // exact data encoded into the image.
                    key: ValueKey('pairing-qr-$_payload'),
                    data: _payload,
                    size: shortestSide * 0.5,
                    backgroundColor: Colors.white,
                  ),
              ],
              SizedBox(height: shortestSide * 0.04),
              // D-pad-accessible way back: autofocused, so select/enter works
              // without any prior navigation.
              _BackToHomeButton(onPressed: () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ),
    );
  }

  String get _payload => PairingCodec.payload(
        host: _host!,
        port: widget.controller.serverPort ?? TvController.defaultServerPort,
        nonce: _nonce,
      );
}

/// The D-pad back affordance: autofocused on entry, with a visible border
/// while focused, and select/enter activation (same pattern as the profile
/// picker's cards).
class _BackToHomeButton extends StatefulWidget {
  const _BackToHomeButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_BackToHomeButton> createState() => _BackToHomeButtonState();
}

class _BackToHomeButtonState extends State<_BackToHomeButton> {
  late final FocusNode _focusNode =
      FocusNode(debugLabel: 'pairing-back-to-home');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      // D-pad center arrives as Select; accept Enter too for emulators.
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      },
      child: FocusableActionDetector(
        focusNode: _focusNode,
        autofocus: true,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onPressed(),
          ),
        },
        child: ListenableBuilder(
          listenable: _focusNode,
          builder: (context, _) {
            final focused = _focusNode.hasFocus;
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: focused
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 4,
                ),
              ),
              child: const Text('Back to home'),
            );
          },
        ),
      ),
    );
  }
}
