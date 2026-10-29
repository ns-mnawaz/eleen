/// The parent-phone home screen: shows the pairing state, opens the
/// scanner, and opens the profiles dashboard once paired.
///
/// On a successful scan the [ScannerScreen] pops with the stored
/// `(base, token)` pair; this screen reports the result and re-reads the
/// [PairedStore]. "Open dashboard" pushes the [ProfilesScreen] with a
/// client pointed at the paired TV.
library;

import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';

import 'pairing/paired_store.dart';
import 'pairing/scanner_screen.dart';
import 'profiles_screen.dart';
import 'widgets/set_pin_dialog.dart';
import '../state/phone_controller.dart';

class PhoneHome extends StatefulWidget {
  const PhoneHome({
    super.key,
    this.store,
    this.pair,
    this.scannerBuilder,
    this.dashboardBuilder,
    this.postPairProvision,
  });

  /// Injectable pairing persistence; defaults to [SharedPrefsPairedStore].
  final PairedStore? store;

  /// Injectable pairing exchange, forwarded to [ScannerScreen].
  final PairFn? pair;

  /// Injectable scanner surface, forwarded to [ScannerScreen] (tests inject
  /// a fake so no camera is needed).
  final WidgetBuilder? scannerBuilder;

  /// Injectable dashboard surface (tests inject a fake so no client is
  /// built). Defaults to [ProfilesScreen] over a real [EleenClient] using
  /// the paired base URI and token.
  final WidgetBuilder? dashboardBuilder;

  /// Injectable post-pair PIN provisioning step, run once after a FRESH
  /// pairing with the new `(base, token)`. The default checks the TV for a
  /// parent PIN and, when none is set, walks the parent through
  /// [_provisionPinAfterPair] (`SetPinDialog` -> `EleenClient.setPin`).
  /// Tests inject a fake so no sockets are opened.
  final Future<void> Function(Uri base, String token)? postPairProvision;

  @override
  State<PhoneHome> createState() => _PhoneHomeState();
}

class _PhoneHomeState extends State<PhoneHome> {
  late final PairedStore _store = widget.store ?? SharedPrefsPairedStore();
  (Uri base, String token)? _paired;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final paired = await _store.load();
      if (!mounted) return;
      setState(() {
        _paired = paired;
        _loading = false;
      });
    } catch (e) {
      // A failing store (corrupt prefs, platform channel down) degrades to
      // the unpaired UI — the user can always re-pair.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openDashboard() async {
    final paired = _paired;
    if (paired == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: widget.dashboardBuilder ??
            (_) => ProfilesScreen(
                  client: EleenClientOps(EleenClient(
                    base: paired.$1,
                    token: paired.$2,
                  )),
                ),
      ),
    );
  }

  Future<void> _openScanner() async {
    final result = await Navigator.push<(Uri, String)>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          store: _store,
          pair: widget.pair ?? defaultPair,
          scannerBuilder: widget.scannerBuilder,
          provisionPin: widget.postPairProvision ?? _provisionPinAfterPair,
        ),
      ),
    );
    if (result != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paired to ${result.$1.host}')),
      );
    }
    await _reload();
  }

  /// The default post-pair provisioning step (handed to [ScannerScreen]):
  /// ask the TV whether a parent PIN is set and, if not, walk the parent
  /// through setting one. A state fetch that fails for any reason skips
  /// the step — provisioning must never block or undo a successful
  /// pairing (the scanner logs and moves on).
  Future<void> _provisionPinAfterPair(Uri base, String token) async {
    final client = EleenClient(base: base, token: token);
    final bool pinSet;
    try {
      pinSet = (await client.state()).parentPinSet;
    } on Object {
      return;
    }
    if (!mounted || pinSet) return;
    await SetPinDialog.show(context, onSubmit: client.setPin);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Eleen')),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_paired != null) ...[
                    const Icon(Icons.tv, size: 48),
                    const SizedBox(height: 12),
                    Text('Paired to ${_paired!.$1.host}:${_paired!.$1.port}',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('open-dashboard'),
                      onPressed: _openDashboard,
                      child: const Text('Open dashboard'),
                    ),
                    const SizedBox(height: 24),
                  ] else ...[
                    const Icon(Icons.tv_off, size: 48),
                    const SizedBox(height: 12),
                    const Text('Not paired yet'),
                    const SizedBox(height: 24),
                  ],
                  FilledButton(
                    onPressed: _openScanner,
                    child: const Text('Scan TV code'),
                  ),
                ],
              ),
      ),
    );
  }
}
