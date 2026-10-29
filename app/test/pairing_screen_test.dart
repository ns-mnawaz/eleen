import 'dart:io';

import 'package:bonsoir/bonsoir.dart';
import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/pairing_screen.dart';
import 'package:eleen/tv/tv_home.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Deterministic [Clock] so the database rows always match "today".
class _FakeClock implements Clock {
  _FakeClock(this.date);

  final DateTime date;

  @override
  int nowMs() => 0;

  @override
  DateTime today() => date;
}

void main() {
  final today = DateTime(2026, 10, 23);

  late EleenDatabase db;
  late TvController controller;

  setUp(() {
    db = EleenDatabase(NativeDatabase.memory());
    controller = TvController(
      db: db,
      clock: _FakeClock(today),
      speedFactor: 1,
    );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<String?> Function()? resolveHost,
    String Function()? generateNonce,
    Future<void> Function(BonsoirService service)? mdnsStart,
    Future<void> Function()? mdnsStop,
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: PairingScreen(
        controller: controller,
        resolveHost: resolveHost ?? () async => null,
        generateNonce: generateNonce ?? () => 'nonce-1',
        mdnsStart: mdnsStart,
        mdnsStop: mdnsStop,
        pollInterval: pollInterval,
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  Future<void> pumpHomeThenOpenPairing(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TvHome(controller: controller),
    ));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('settings-pairing')));
    // Route transition: fixed pumps — the resolving spinner (default host
    // lookup pending in fake async) never settles for pumpAndSettle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('QR renders the eleen://pair payload with host, port and nonce',
      (WidgetTester tester) async {
    await pumpScreen(
      tester,
      resolveHost: () async => '192.168.1.50',
      generateNonce: () => 'nonce-1',
    );

    // The payload is exposed via the QR view's ValueKey so tests can read
    // the exact data encoded into the image.
    expect(
      find.byKey(const ValueKey(
          'pairing-qr-eleen://pair?host=192.168.1.50&port=8477&nonce=nonce-1')),
      findsOneWidget,
    );
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('uses the live server port when the server is running',
      (WidgetTester tester) async {
    // Bind on an ephemeral loopback port; the QR must carry the port the
    // server actually bound, not a hardcoded copy of the default.
    await tester
        .runAsync(
            () => controller.startServer(address: InternetAddress.loopbackIPv4, port: 0))
        .timeout(const Duration(seconds: 5));
    final port = controller.serverPort;
    expect(port, isNotNull);

    await pumpScreen(
      tester,
      resolveHost: () async => '192.168.1.50',
      generateNonce: () => 'nonce-1',
    );

    expect(
      find.byKey(ValueKey(
          'pairing-qr-eleen://pair?host=192.168.1.50&port=$port&nonce=nonce-1')),
      findsOneWidget,
    );

    // Leave no poll timer or server socket running when the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(controller.stopServer);
  });

  testWidgets('each open generates a fresh nonce', (WidgetTester tester) async {
    var opens = 0;
    String nonce() => 'nonce-${++opens}';

    await pumpScreen(tester,
        resolveHost: () async => '192.168.1.50', generateNonce: nonce);
    expect(
      find.byKey(const ValueKey(
          'pairing-qr-eleen://pair?host=192.168.1.50&port=8477&nonce=nonce-1')),
      findsOneWidget,
    );

    // Re-open: a brand new screen (fresh state) must encode a new nonce.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await pumpScreen(tester,
        resolveHost: () async => '192.168.1.50', generateNonce: nonce);
    expect(
      find.byKey(const ValueKey(
          'pairing-qr-eleen://pair?host=192.168.1.50&port=8477&nonce=nonce-2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey(
          'pairing-qr-eleen://pair?host=192.168.1.50&port=8477&nonce=nonce-1')),
      findsNothing,
    );
  });

  testWidgets('shows a clear error state when no TV address can be found',
      (WidgetTester tester) async {
    await pumpScreen(tester, resolveHost: () async => null);

    expect(find.text('Could not determine TV address — check Wi-Fi'),
        findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('shows "Pairing complete" once the token appears in settings',
      (WidgetTester tester) async {
    await pumpScreen(
      tester,
      resolveHost: () async => '192.168.1.50',
      generateNonce: () => 'nonce-1',
      pollInterval: const Duration(milliseconds: 100),
    );
    expect(find.byType(QrImageView), findsOneWidget);

    // The phone app pairs: the server stores a token in settings.
    final settings = await db.getSettings();
    await db.saveSettings(Settings(
      parentPin: settings.parentPin,
      token: 'pair-token',
      masterLockEnabled: settings.masterLockEnabled,
    ));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('Pairing complete ✓'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('re-pairing (token rotation) also shows the success state',
      (WidgetTester tester) async {
    final settings = await db.getSettings();
    await db.saveSettings(Settings(
      parentPin: settings.parentPin,
      token: 'old-token',
      masterLockEnabled: settings.masterLockEnabled,
    ));

    await pumpScreen(
      tester,
      resolveHost: () async => '192.168.1.50',
      generateNonce: () => 'nonce-1',
      pollInterval: const Duration(milliseconds: 100),
    );
    // Already paired: the QR still shows so a re-pair can rotate the token.
    expect(find.byType(QrImageView), findsOneWidget);

    await db.saveSettings(Settings(
      parentPin: settings.parentPin,
      token: 'rotated-token',
      masterLockEnabled: settings.masterLockEnabled,
    ));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.text('Pairing complete ✓'), findsOneWidget);
  });

  testWidgets('registers the Eleen-TV mDNS service on open and stops it on '
      'leave', (WidgetTester tester) async {
    BonsoirService? registered;
    var stopped = false;

    await pumpScreen(
      tester,
      resolveHost: () async => '192.168.1.50',
      generateNonce: () => 'nonce-1',
      mdnsStart: (service) async => registered = service,
      mdnsStop: () async => stopped = true,
    );

    expect(registered, isNotNull);
    expect(registered!.name, 'Eleen-TV');
    expect(registered!.type, '_eleen._tcp');
    expect(registered!.port, 8477);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(stopped, isTrue);
  });

  testWidgets('a failed mDNS registration does not break the screen',
      (WidgetTester tester) async {
    await pumpScreen(
      tester,
      resolveHost: () async => '192.168.1.50',
      generateNonce: () => 'nonce-1',
      mdnsStart: (service) => Future.error(Exception('mDNS unavailable')),
      mdnsStop: () async {},
    );

    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('pairing screen is reachable from the TV home settings row and '
      'D-pad Back returns home', (WidgetTester tester) async {
    await pumpHomeThenOpenPairing(tester);

    expect(find.text('Back to home'), findsOneWidget);

    // D-pad select on the autofocused back affordance returns home.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Back to home'), findsNothing);
  });
}
