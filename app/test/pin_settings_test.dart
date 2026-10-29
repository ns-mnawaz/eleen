// TV-side parent-PIN management: the "PIN" entry in the home settings row
// opens the management screen — set (enter + confirm), change (current +
// new + confirm) and remove (current -> cleared). All through the
// coordinator's settings (the db is the source of truth), so the TV can
// manage the PIN standalone, without the phone.

import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/pin_settings.dart';
import 'package:eleen/tv/tv_home.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClock implements Clock {
  _FakeClock(this.date);

  final DateTime date;

  @override
  int nowMs() => 0;

  @override
  DateTime today() => date;
}

void main() {
  final today = DateTime(2026, 10, 24);

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

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PinSettingsSheet(controller: controller),
      ),
    ));
    await tester.pump();
  }

  Future<void> enterDigits(
      WidgetTester tester, Iterable<String> digits) async {
    for (final digit in digits) {
      await tester.tap(find.byKey(Key('pin-key-$digit')));
      await tester.pump();
    }
  }

  testWidgets('no PIN set: the sheet opens straight into the set flow — '
      'enter + confirm saves through the coordinator settings',
      (tester) async {
    await pumpSheet(tester);

    // No menu: the set flow is the whole sheet.
    expect(find.byKey(const Key('pin-settings-change')), findsNothing);
    expect(find.byKey(const Key('pin-settings-remove')), findsNothing);
    expect(find.text('Set a parent PIN'), findsOneWidget);

    await enterDigits(tester, '1234'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    // Confirm stage.
    expect(find.textContaining('Confirm'), findsOneWidget);
    await enterDigits(tester, '1234'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    // The db (source of truth) now holds the PIN.
    expect((await db.getSettings()).parentPin, '1234');
    expect(find.textContaining('PIN saved'), findsOneWidget);
  });

  testWidgets('no PIN set: a mismatched confirmation errors and saves '
      'nothing', (tester) async {
    await pumpSheet(tester);

    await enterDigits(tester, '1234'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();
    await enterDigits(tester, '9999'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    expect(find.text('PINs do not match'), findsOneWidget);
    expect((await db.getSettings()).parentPin, isEmpty);
    // Back at the first entry stage for a retry.
    expect(find.text('Set a parent PIN'), findsOneWidget);
  });

  testWidgets('no PIN set: a too-short PIN is rejected', (tester) async {
    await pumpSheet(tester);

    await enterDigits(tester, '123'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    expect(find.text('Use at least 4 digits'), findsOneWidget);
    expect((await db.getSettings()).parentPin, isEmpty);
  });

  testWidgets('PIN set: the sheet offers Change and Remove', (tester) async {
    await db.saveSettings(const Settings(parentPin: '1234'));
    await pumpSheet(tester);

    expect(find.byKey(const Key('pin-settings-change')), findsOneWidget);
    expect(find.byKey(const Key('pin-settings-remove')), findsOneWidget);
  });

  testWidgets('change: a wrong current PIN errors and changes nothing',
      (tester) async {
    await db.saveSettings(const Settings(parentPin: '1234'));
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('pin-settings-change')));
    await tester.pump();
    await enterDigits(tester, '0000'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    expect(find.text('Wrong PIN'), findsOneWidget);
    expect((await db.getSettings()).parentPin, '1234');
  });

  testWidgets('change: current + new + confirm updates the PIN',
      (tester) async {
    await db.saveSettings(const Settings(parentPin: '1234'));
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('pin-settings-change')));
    await tester.pump();
    await enterDigits(tester, '1234'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();
    await enterDigits(tester, '5678'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();
    await enterDigits(tester, '5678'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    expect((await db.getSettings()).parentPin, '5678');
    expect(find.textContaining('PIN saved'), findsOneWidget);
  });

  testWidgets('remove: the current PIN clears it (back to no PIN)',
      (tester) async {
    await db.saveSettings(const Settings(parentPin: '1234'));
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('pin-settings-remove')));
    await tester.pump();
    await enterDigits(tester, '1234'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    expect((await db.getSettings()).parentPin, isEmpty);
    expect(find.textContaining('PIN removed'), findsOneWidget);
  });

  testWidgets('remove: a wrong current PIN clears nothing', (tester) async {
    await db.saveSettings(const Settings(parentPin: '1234'));
    await pumpSheet(tester);

    await tester.tap(find.byKey(const Key('pin-settings-remove')));
    await tester.pump();
    await enterDigits(tester, '0000'.split(''));
    await tester.tap(find.byKey(const Key('pin-settings-next')));
    await tester.pump();

    expect(find.text('Wrong PIN'), findsOneWidget);
    expect((await db.getSettings()).parentPin, '1234');
  });

  testWidgets('the TV home settings row opens the sheet', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: TvHome(controller: controller),
    ));
    await tester.pump();

    expect(find.byKey(const Key('settings-pin')), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-pin')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pin-settings')), findsOneWidget);
  });

  testWidgets('the 4th digit hands D-pad focus to the Next button',
      (tester) async {
    await pumpSheet(tester);

    await enterDigits(tester, ['1', '2', '3']);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        isNot('pin-settings-next'),
        reason: 'focus is still on the pad after 3 digits');

    await enterDigits(tester, ['4']);
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel,
        'pin-settings-next',
        reason: 'the 4th digit must move focus to the action button');
  });
}
