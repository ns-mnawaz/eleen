import 'dart:async';
import 'dart:io';

import 'package:eleen/phone/pairing/paired_store.dart';
import 'package:eleen/phone/pairing/scanner_screen.dart';
import 'package:eleen/phone/phone_home.dart';
import 'package:eleen/phone/widgets/set_pin_dialog.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory [PairedStore] so tests never touch platform channels.
class _FakeStore implements PairedStore {
  Uri? base;
  String? token;
  int saves = 0;

  @override
  Future<void> save(Uri base, String token) async {
    saves++;
    this.base = base;
    this.token = token;
  }

  @override
  Future<(Uri, String)?> load() async =>
      base == null ? null : (base!, token!);

  @override
  Future<void> clear() async {
    base = null;
    token = null;
  }
}

/// A [PairedStore] whose load always throws, guarding PhoneHome's degraded
/// path.
class _BrokenStore implements PairedStore {
  @override
  Future<void> save(Uri base, String token) async {}

  @override
  Future<(Uri, String)?> load() async => throw Exception('disk exploded');

  @override
  Future<void> clear() async {}
}

const _goodPayload =
    'eleen://pair?host=192.168.1.50&port=8477&nonce=nonce-1';

/// A [PairedStore] whose save always throws (corrupt prefs / platform
/// channel down).
class _BrokenSaveStore implements PairedStore {
  @override
  Future<void> save(Uri base, String token) async =>
      throw Exception('prefs broken');

  @override
  Future<(Uri, String)?> load() async => null;

  @override
  Future<void> clear() async {}
}

void main() {
  group('ScannerScreen', () {
    late _FakeStore store;
    late Uri? pairBase;
    late String? pairNonce;
    late Object? pairError;

    /// Pair function the tests inject; records its arguments.
    Future<String> recordPair(Uri base, String nonce) async {
      pairBase = base;
      pairNonce = nonce;
      if (pairError != null) throw pairError!;
      return 'pair-token';
    }

    Widget scanner() => ScannerScreen(
          store: store,
          pair: recordPair,
          // Tests inject scanner results; no camera needed.
          scannerBuilder: (context) => const Text('fake-scanner'),
        );

    /// Feeds [value] into the screen as if the scanner had read a barcode.
    Future<void> inject(WidgetTester tester, String value) async {
      final key = GlobalKey<ScannerScreenState>();
      await tester.pumpWidget(MaterialApp(
          home: ScannerScreen(
        key: key,
        store: store,
        pair: recordPair,
        scannerBuilder: (context) => const Text('fake-scanner'),
      )));
      key.currentState!.handleScannedValue(value);
      await tester.pump();
    }

    setUp(() {
      store = _FakeStore();
      pairBase = null;
      pairNonce = null;
      pairError = null;
    });

    testWidgets('renders the injected scanner surface', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: ScannerScreen(
              store: store, pair: recordPair, scannerBuilder: (c) => const Text('fake-scanner'))));
      expect(find.text('fake-scanner'), findsOneWidget);
    });

    testWidgets('payload parse routes to pair with extracted host/port/nonce '
        'and persists the token', (tester) async {
      await inject(tester, _goodPayload);

      expect(pairBase, Uri.parse('http://192.168.1.50:8477'));
      expect(pairNonce, 'nonce-1');
      expect(store.saves, 1);
      expect(store.base, Uri.parse('http://192.168.1.50:8477'));
      expect(store.token, 'pair-token');
    });

    testWidgets('successful pair pops with the stored base and token',
        (tester) async {
      (Uri, String)? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                final r = await Navigator.push<(Uri, String)>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ScannerScreen(
                      store: store,
                      pair: recordPair,
                      scannerBuilder: (c) => const Text('fake-scanner'),
                    ),
                  ),
                );
                result = r;
              },
              child: const Text('open'),
            );
          },
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final key = tester
          .state<ScannerScreenState>(find.byType(ScannerScreen));
      key.handleScannedValue(_goodPayload);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.$1, Uri.parse('http://192.168.1.50:8477'));
      expect(result!.$2, 'pair-token');
      // Back at the harness home.
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('bad payload shows an error and never calls pair',
        (tester) async {
      await inject(tester, 'https://example.com/not-eleen');

      expect(find.text('Not a valid Eleen pairing code'), findsOneWidget);
      expect(pairBase, isNull);
      expect(store.saves, 0);
    });

    testWidgets('stale nonce (401) asks the parent for a new code',
        (tester) async {
      pairError = const EleenApiError(401);
      await inject(tester, _goodPayload);

      expect(
          find.text('Pairing code expired — ask parent to show a new code'),
          findsOneWidget);
      expect(store.saves, 0);
    });

    testWidgets('TV unreachable (EleenOffline) shows the same-network hint',
        (tester) async {
      pairError = EleenOffline(const SocketException('refused'));
      await inject(tester, _goodPayload);

      expect(
          find.text('TV offline — check both devices are on the same Wi-Fi'),
          findsOneWidget);
      expect(store.saves, 0);
    });

    testWidgets('raw HttpException escaping the client is treated as offline',
        (tester) async {
      // client.dart's _send only maps SocketException -> EleenOffline; a raw
      // HttpException-family error must still land in the offline UI.
      pairError = const HttpException('connection closed');
      await inject(tester, _goodPayload);

      expect(
          find.text('TV offline — check both devices are on the same Wi-Fi'),
          findsOneWidget);
      expect(store.saves, 0);
    });

    testWidgets('other API errors surface their status', (tester) async {
      pairError = const EleenApiError(500);
      await inject(tester, _goodPayload);

      expect(find.text('Pairing failed (HTTP 500)'), findsOneWidget);
      expect(store.saves, 0);
    });

    testWidgets('manual fallback pairs from a pasted eleen://pair code',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: scanner()));
      await tester.enterText(
          find.byKey(const Key('manual-payload')), _goodPayload);
      await tester.tap(find.byKey(const Key('manual-submit')));
      await tester.pump();

      expect(pairBase, Uri.parse('http://192.168.1.50:8477'));
      expect(pairNonce, 'nonce-1');
      expect(store.token, 'pair-token');
    });

    testWidgets('manual fallback rejects a bare address with guidance',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: scanner()));
      await tester.enterText(
          find.byKey(const Key('manual-payload')), '192.168.1.50:8477');
      await tester.tap(find.byKey(const Key('manual-submit')));
      await tester.pump();

      expect(pairBase, isNull);
      expect(find.textContaining('one-time code'), findsOneWidget);
    });

    testWidgets('busy state ignores further payloads mid-pair',
        (tester) async {
      // A pair call that never completes until the test releases it.
      final gate = Completer<String>();
      final key = GlobalKey<ScannerScreenState>();
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        home: ScannerScreen(
          key: key,
          store: store,
          pair: (base, nonce) {
            calls++;
            return gate.future;
          },
          scannerBuilder: (context) => const Text('fake-scanner'),
        ),
      ));
      key.currentState!.handleScannedValue(_goodPayload);
      await tester.pump();
      // QR frames keep arriving while the first pair is in flight.
      key.currentState!.handleScannedValue(_goodPayload);
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets('a late error after a mid-pair back does not throw',
        (tester) async {
      // Pair in flight, user backs out, the exchange then fails: the
      // error path must hit the mounted guard instead of setState-after-
      // dispose.
      final gate = Completer<String>();
      final key = GlobalKey<ScannerScreenState>();
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push<(Uri, String)>(
              context,
              MaterialPageRoute(
                builder: (_) => ScannerScreen(
                  key: key,
                  store: store,
                  pair: (_, _) => gate.future,
                  scannerBuilder: (c) => const Text('fake-scanner'),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      key.currentState!.handleScannedValue(_goodPayload);
      await tester.pump();

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      gate.completeError(const EleenApiError(401));
      await tester.pump();

      // Back at the harness home, no framework exception, no crash.
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('a store.save failure surfaces as UI feedback and stays up',
        (tester) async {
      final key = GlobalKey<ScannerScreenState>();
      await tester.pumpWidget(MaterialApp(
        home: ScannerScreen(
          key: key,
          store: _BrokenSaveStore(),
          pair: (base, nonce) async => 'pair-token',
          scannerBuilder: (context) => const Text('fake-scanner'),
        ),
      ));
      key.currentState!.handleScannedValue(_goodPayload);
      await tester.pump();

      expect(
          find.text('Paired with the TV, but the token could not be saved on '
              'this device — try again'),
          findsOneWidget);
      // Still on the scanner screen (did not pop as if paired).
      expect(find.byKey(const Key('manual-payload')), findsOneWidget);
    });
  });

  group('SharedPrefsPairedStore', () {
    test('save, load and clear round-trip through mock prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPrefsPairedStore();
      expect(await store.load(), isNull);

      final base = Uri.parse('http://192.168.1.50:8477');
      await store.save(base, 'tok-1');
      final loaded = await store.load();
      expect(loaded, isNotNull);
      expect(loaded!.$1, base);
      expect(loaded.$2, 'tok-1');

      await store.clear();
      expect(await store.load(), isNull);
    });
  });

  group('PhoneHome', () {
    testWidgets('unpaired home offers the scanner and pushes it on tap',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PhoneHome(
          store: _FakeStore(),
          scannerBuilder: (context) => const Text('fake-scanner'),
        ),
      ));
      await tester.pump();

      expect(find.text('Not paired yet'), findsOneWidget);
      await tester.tap(find.text('Scan TV code'));
      await tester.pumpAndSettle();
      expect(find.text('fake-scanner'), findsOneWidget);
    });

    testWidgets('a previously paired store shows the TV address',
        (tester) async {
      final store = _FakeStore()
        ..base = Uri.parse('http://192.168.1.50:8477')
        ..token = 'tok';
      await tester.pumpWidget(MaterialApp(home: PhoneHome(store: store)));
      await tester.pump();

      expect(find.text('Paired to 192.168.1.50:8477'), findsOneWidget);
    });

    testWidgets('a failing store degrades to the unpaired UI instead of '
        'crashing', (tester) async {
      await tester.pumpWidget(MaterialApp(home: PhoneHome(store: _BrokenStore())));
      await tester.pump();

      expect(find.text('Not paired yet'), findsOneWidget);
    });

    testWidgets('a fresh pair runs the post-pair provisioning step with the '
        'new base and token', (tester) async {
      final provisions = <(Uri, String)>[];
      await tester.pumpWidget(MaterialApp(
        home: PhoneHome(
          store: _FakeStore(),
          pair: (base, nonce) async => 'pair-token',
          scannerBuilder: (context) => const Text('fake-scanner'),
          postPairProvision: (base, token) async =>
              provisions.add((base, token)),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Scan TV code'));
      await tester.pumpAndSettle();
      tester
          .state<ScannerScreenState>(find.byType(ScannerScreen))
          .handleScannedValue(_goodPayload);
      await tester.pumpAndSettle();

      expect(provisions, [
        (Uri.parse('http://192.168.1.50:8477'), 'pair-token'),
      ]);
      // Back at the home screen after the (injected, instant) step.
      expect(find.text('Scan TV code'), findsOneWidget);
    });
  });

  group('SetPinDialog', () {
    /// Opens the dialog via a harness button; returns a getter for the
    /// dialog's eventual result (null while it is still open).
    Future<bool? Function()> openDialog(
      WidgetTester tester,
      Future<void> Function(String pin) onSubmit,
    ) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return TextButton(
          onPressed: () {
            SetPinDialog.show(context, onSubmit: onSubmit)
                .then((v) => result = v);
          },
          child: const Text('open'),
        );
      })));
      bool? getter() => result;
      return getter;
    }

    Future<void> pumpOpen(WidgetTester tester) async {
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('4 digits in each field advance focus down the chain',
        (tester) async {
      final result = await openDialog(tester, (pin) async {});
      await pumpOpen(tester);

      // After the 4th digit of the PIN, focus jumps to the confirm field.
      await tester.enterText(find.byKey(const Key('setpin-field')), '1357');
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel,
          'setpin-confirm');

      // After the 4th digit of the confirmation, focus jumps to Save PIN.
      await tester.enterText(find.byKey(const Key('setpin-confirm')), '1357');
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'setpin-submit');
      expect(result(), isNull);
    });

    testWidgets('rejects a short PIN without calling onSubmit', (tester) async {
      var submitted = '';
      final result = await openDialog(tester, (pin) async => submitted = pin);
      await pumpOpen(tester);

      await tester.enterText(find.byKey(const Key('setpin-field')), '12');
      await tester.enterText(find.byKey(const Key('setpin-confirm')), '12');
      await tester.tap(find.byKey(const Key('setpin-submit')));
      await tester.pump();

      expect(find.text('Use at least 4 digits'), findsOneWidget);
      expect(find.byKey(const Key('setpin-field')), findsOneWidget);
      expect(submitted, isEmpty);
      expect(result(), isNull);
    });

    testWidgets('rejects a mismatched confirmation', (tester) async {
      var submitted = '';
      final result = await openDialog(tester, (pin) async => submitted = pin);
      await pumpOpen(tester);

      await tester.enterText(find.byKey(const Key('setpin-field')), '1357');
      await tester.enterText(find.byKey(const Key('setpin-confirm')), '2468');
      await tester.tap(find.byKey(const Key('setpin-submit')));
      await tester.pump();

      expect(find.text('PINs do not match'), findsOneWidget);
      expect(submitted, isEmpty);
      expect(result(), isNull);
    });

    testWidgets('submits the confirmed PIN and pops true', (tester) async {
      String? submitted;
      final result = await openDialog(tester, (pin) async => submitted = pin);
      await pumpOpen(tester);

      await tester.enterText(find.byKey(const Key('setpin-field')), '1357');
      await tester.enterText(find.byKey(const Key('setpin-confirm')), '1357');
      await tester.tap(find.byKey(const Key('setpin-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(submitted, '1357');
      expect(result(), isTrue);
      expect(find.byKey(const Key('setpin-field')), findsNothing);
    });

    testWidgets('a failing onSubmit shows the error inline and stays open',
        (tester) async {
      final result = await openDialog(
        tester,
        (pin) async => throw const EleenApiError(500, 'boom'),
      );
      await pumpOpen(tester);

      await tester.enterText(find.byKey(const Key('setpin-field')), '1357');
      await tester.enterText(find.byKey(const Key('setpin-confirm')), '1357');
      await tester.tap(find.byKey(const Key('setpin-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('TV error (HTTP 500)'), findsOneWidget);
      expect(find.byKey(const Key('setpin-field')), findsOneWidget);
      expect(result(), isNull);
    });

    testWidgets('skip pops false without calling onSubmit', (tester) async {
      var submitted = '';
      final result = await openDialog(tester, (pin) async => submitted = pin);
      await pumpOpen(tester);

      // The explicit "Skip for now" path: the parent can defer PIN setup —
      // it must not block pairing completion or dashboard access.
      expect(find.text('Skip for now'), findsOneWidget);
      await tester.tap(find.byKey(const Key('setpin-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(submitted, isEmpty);
      expect(result(), isFalse);
      expect(find.byKey(const Key('setpin-field')), findsNothing);
    });
  });
}
