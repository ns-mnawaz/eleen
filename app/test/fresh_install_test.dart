// End-to-end widget proof of the fresh-install path against a REAL
// in-process EleenServer (loopback, real HTTP, nothing seeded — no PIN, no
// profiles):
//
//   pair on the phone -> the TV reports `parentPinSet == false` so the
//   post-pair provisioning dialog appears -> the parent sets a PIN ->
//   create the first profile with that PIN -> add-time with that PIN
//   succeeds (the unlock gate is reachable on a real install).
//
// Widget tests use a fake event loop, so every window that waits on real
// network round-trips is bracketed in `tester.runAsync`.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:eleen/phone/pairing/paired_store.dart';
import 'package:eleen/phone/pairing/scanner_screen.dart';
import 'package:eleen/phone/phone_home.dart';
import 'package:eleen/phone/profiles_screen.dart';
import 'package:eleen/state/phone_controller.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [PairedStore] so tests never touch platform channels.
class _FakeStore implements PairedStore {
  Uri? base;
  String? token;

  @override
  Future<void> save(Uri base, String token) async {
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

void main() {
  late EleenDatabase db;
  late EngineCoordinator coordinator;
  late EleenServer server;

  setUpAll(() {
    // Init the binding first (it installs its 400-mock HttpClient override),
    // then restore real HttpClient creation: this file deliberately talks to
    // a real in-process loopback server.
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  });

  setUp(() async {
    db = EleenDatabase(NativeDatabase.memory());
    coordinator = EngineCoordinator(
      db: db,
      engine: TimeEngine(clock: SystemClock()),
    );
    server = EleenServer(coordinator: coordinator);
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
  });

  tearDown(() async {
    await server.stop();
    await db.close();
  });

  /// Runs [body] in a real-async window so real HTTP round-trips to the
  /// loopback server get their wall-clock time to finish before the next
  /// pump.
  ///
  /// The widget-test binding normally mocks every `HttpClient` to a stub
  /// that answers 400 (a global `HttpOverrides` installed at binding
  /// init); setUpAll clears it for this file, restoring real clients.
  Future<void> runRealAsync(
    WidgetTester tester,
    Future<void> Function() body, [
    int ms = 700,
  ]) async {
    await tester.runAsync(() async {
      await body();
      await Future<void>.delayed(Duration(milliseconds: ms));
    });
    // Settle what the window closed: dialog exits, route pops (their
    // animations are fake-ticked and need advanced fake time).
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  /// Opens the scanner and feeds it [payload]. The whole pairing exchange
  /// (pair -> save -> provisioning state-fetch -> provisioning dialog up)
  /// runs inside the real-async window; the dialog then stays open waiting
  /// for the parent. (No pumpAndSettle here: the open dialog keeps
  /// scheduling frames — cursor blink over the scanner's busy spinner.)
  Future<void> pairViaPayload(WidgetTester tester, String payload) async {
    await tester.tap(find.text('Scan TV code'));
    await tester.pumpAndSettle();
    await runRealAsync(tester, () async {
      tester
          .state<ScannerScreenState>(find.byType(ScannerScreen))
          .handleScannedValue(payload);
    });
  }

  testWidgets('fresh install: pair -> set parent PIN -> create profile -> '
      'add time with that PIN succeeds', (tester) async {
    final nonce = PairingCodec.newNonce();
    server.registerNonce(nonce);
    final payload = PairingCodec.payload(
      host: '127.0.0.1',
      port: server.port,
      nonce: nonce,
    );

    final store = _FakeStore();
    PhoneController? dashboardController;
    await tester.binding.setSurfaceSize(const Size(1100, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: PhoneHome(
        store: store,
        // No camera in tests; scanning results enter via the state handle.
        scannerBuilder: (_) => const Text('fake-scanner'),
        // The dashboard gets the controller pre-built (below) inside a
        // real-async window, so its initial fetch is real HTTP.
        dashboardBuilder: (_) => ProfilesScreen(
          client: EleenClientOps(
              EleenClient(base: store.base!, token: store.token!)),
          controller: dashboardController,
          pollInterval: const Duration(hours: 1),
        ),
      ),
    ));
    await tester.pump();

    await pairViaPayload(tester, payload);

    // Fresh TV (no PIN): the provisioning dialog is up over the scanner.
    expect(find.byKey(const Key('setpin-field')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('setpin-field')), '1357');
    await tester.enterText(find.byKey(const Key('setpin-confirm')), '1357');
    await runRealAsync(
        tester, () => tester.tap(find.byKey(const Key('setpin-submit'))));
    await tester.pumpAndSettle();

    // The dialog closed on success and the TV now holds the PIN.
    expect(find.byKey(const Key('setpin-field')), findsNothing);
    expect(store.token, isNotNull);
    expect((await db.getSettings()).parentPin, '1357');

    // Wait out the pairing snackbar (it sits over the centered buttons;
    // its timer is real, since it is shown from the real-async pairing
    // chain — so wait in real time, not fake pump time).
    await runRealAsync(tester, () async {}, 4600);

    // Open the dashboard over the still-empty TV. The push itself happens
    // in the fake zone (so its route transition is fake-ticked and the FAB
    // lands inside the surface); the dashboard's controller is pre-built in
    // a real-async window so its initial fetch uses real HTTP.
    await runRealAsync(tester, () async {
      dashboardController = PhoneController(
        client: EleenClientOps(EleenClient(base: store.base!, token: store.token!)),
        // No polling: the test drives every fetch explicitly.
        pollInterval: const Duration(hours: 1),
      );
    });
    addTearDown(dashboardController!.dispose);
    await tester.tap(find.byKey(const Key('open-dashboard')));
    await tester.pump();
    await tester.pump();

    // Empty dashboard points at the create form; open it.
    await tester.tap(find.byKey(const Key('add-profile-empty')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('create-name')), 'Maya');
    await tester.tap(find.byKey(const Key('create-allowance-15')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('create-submit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('pin-field')), '1357');
    // PinDialog.run drives the create call itself; the round-trips (create
    // + controller refresh) happen inside this window.
    await runRealAsync(
        tester, () => tester.tap(find.byKey(const Key('pin-submit'))));
    // The dialogs' exit transitions need real pump cycles to finish.
    await tester.pumpAndSettle();

    expect(find.text('Maya'), findsOneWidget,
        reason: 'the created profile row is on the dashboard');

    // Now reach an unlock-gated action with the provisioned PIN: add time.
    await tester.tap(find.text('Add time'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byKey(const Key('pin-field')), '1357');
    await tester.tap(find.byKey(const Key('pin-submit')));
    await tester.pump();
    await runRealAsync(
        tester, () => tester.tap(find.byKey(const Key('add-amount-30'))));
    await tester.pumpAndSettle();

    // Dialog closed on success; 15-minute allowance + 30 added minutes.
    expect(find.byKey(const Key('add-amounts')), findsNothing);
    expect(find.textContaining('45:00 left'), findsOneWidget);

    // The TV-side state agrees.
    final st = await coordinator.state();
    expect(st.profiles, hasLength(1));
    expect(st.remainingByProfile[st.profiles.single.id], (15 + 30) * 60);
  });

  testWidgets('a TV that already has a PIN does not prompt after pairing',
      (tester) async {
    await db.saveSettings(const Settings(parentPin: '2468'));
    final nonce = PairingCodec.newNonce();
    server.registerNonce(nonce);
    final payload = PairingCodec.payload(
      host: '127.0.0.1',
      port: server.port,
      nonce: nonce,
    );

    await tester.pumpWidget(MaterialApp(
      home: PhoneHome(
        store: _FakeStore(),
        scannerBuilder: (_) => const Text('fake-scanner'),
      ),
    ));
    await tester.pump();

    await pairViaPayload(tester, payload);

    // Provisioning skipped: the PIN is already set (e.g. a re-pair).
    expect(find.byKey(const Key('setpin-field')), findsNothing);
    expect((await db.getSettings()).parentPin, '2468');
  });
}
