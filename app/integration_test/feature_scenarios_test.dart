// Executable form of the cucumber specs in docs/testing/features/.
//
// Each group names the feature file it implements. Runs on the live
// `eleen_tv` emulator through `tool/run_e2e.sh` (it keeps the
// SYSTEM_ALERT_WINDOW permission granted — the denied-permission banner
// shifts the home layout and would break unrelated assertions):
//
//   flutter test integration_test/feature_scenarios_test.dart \
//       --dart-define=ELEN_FAST=1 -d emulator-5556
//
// @real-device scenarios (camera QR scan, SYSTEM_ALERT_WINDOW render) are
// deliberately absent — they stay on the manual checklist.

import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/profile_form.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/tv_harness.dart';

const _timeout = Timeout(Duration(minutes: 4));

/// Types the parent PIN on the on-screen pad (tap path).
Future<void> tapPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(Key('pin-key-$digit')));
    await pumpFor(tester, const Duration(milliseconds: 120));
  }
}

/// The debugLabel of the currently focused node.
String? focusedLabel() =>
    FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  ensureE2eBinding();

  if (runTvScenarios) {
    // ------------------------------------------------------- profile_form
    group('profile_form.feature', () {
      Future<void> openCreateForm(WidgetTester tester) async {
        await seedDeviceTvDb(parentPin: e2eParentPin);
        await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
        await waitForFound(
          tester,
          find.byKey(const Key('add-profile-card')),
          const Duration(seconds: 60),
          context: 'picker',
        );
        await tester.tap(find.byKey(const Key('add-profile-card')));
        await waitForFound(
          tester,
          find.byKey(const Key('parent-pin-prompt')),
          const Duration(seconds: 15),
          context: 'create-form PIN gate',
        );
        await tapPin(tester, e2eParentPin);
        await waitForFound(
          tester,
          find.byKey(const Key('profile-form')),
          const Duration(seconds: 15),
          context: 'create form',
        );
      }

      testWidgets(
        'name is required: empty save shows "Enter a name", form stays open',
        (tester) async {
          await openCreateForm(tester);

          await tester.tap(find.byKey(const Key('profile-form-save')));
          await pumpFor(tester, const Duration(milliseconds: 500));

          expect(find.byKey(const Key('profile-form')), findsOneWidget);
          expect(find.byKey(const Key('profile-form-error')), findsOneWidget);
          expect(find.text('Enter a name'), findsOneWidget);

          final db = await openDeviceTvDb();
          final profiles = await db.allProfiles();
          await db.close();
          expect(profiles.where((p) => p.id != 'e2e-kid'), isEmpty,
              reason: 'no profile created on a rejected save');
        },
        timeout: _timeout,
      );

      testWidgets(
        'whitespace-only name is treated as empty',
        (tester) async {
          await openCreateForm(tester);
          await tester.enterText(
              find.byKey(const Key('profile-form-name')), '   ');
          await tester.pump();
          await tester.tap(find.byKey(const Key('profile-form-save')));
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.text('Enter a name'), findsOneWidget);
          expect(find.byKey(const Key('profile-form')), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'cancel returns to the picker without saving',
        (tester) async {
          await openCreateForm(tester);
          await tester.enterText(
              find.byKey(const Key('profile-form-name')), 'TestKid');
          await tester.pump();
          await tester.tap(find.byKey(const Key('profile-form-cancel')));

          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 15),
            context: 'picker after cancel',
          );
          // The form route is still animating out when the picker first
          // shows beneath it; wait for the pop to finish.
          await waitForGone(
            tester,
            find.byKey(const Key('profile-form')),
            const Duration(seconds: 15),
          );

          final db = await openDeviceTvDb();
          final profiles = await db.allProfiles();
          await db.close();
          expect(profiles.any((p) => p.name == 'TestKid'), isFalse);
        },
        timeout: _timeout,
      );

      testWidgets(
        'form opens with focus on the first avatar chip, not the name field',
        (tester) async {
          await openCreateForm(tester);
          // Let the route transition finish so autofocus can land.
          await pumpFor(tester, const Duration(seconds: 1));
          expect(focusedLabel(), 'profile-form-first-avatar',
              reason: 'initial focus must not summon the IME on a TV');
        },
        timeout: _timeout,
      );

      testWidgets(
        'Done on the name keyboard moves focus to the avatar chips',
        (tester) async {
          await openCreateForm(tester);

          // Focus the name field deliberately and type a name.
          await tester.tap(find.byKey(const Key('profile-form-name')));
          await tester.pump();
          expect(focusedLabel(), 'profile-form-name');
          await tester.enterText(
              find.byKey(const Key('profile-form-name')), 'TestKid');
          await tester.pump();

          // The keyboard's Done key.
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await pumpFor(tester, const Duration(milliseconds: 500));

          expect(focusedLabel(), 'profile-form-first-avatar',
              reason: 'Done must release the field, not trap it');
        },
        timeout: _timeout,
      );

      testWidgets(
        'D-pad Down from the avatar chips never bounces back to the name '
        'field before the actions',
        (tester) async {
          await openCreateForm(tester);
          await tester.pump();
          expect(focusedLabel(), 'profile-form-first-avatar');

          final visited = <String?>[];
          for (var i = 0; i < 6; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
            await pumpFor(tester, const Duration(milliseconds: 200));
            visited.add(focusedLabel());
          }

          // Traversal moves on; it must not land back on the name field
          // (that would re-summon the IME and trap the D-pad user).
          expect(visited.where((l) => l == 'profile-form-name'), isEmpty,
              reason: 'visited: $visited');
        },
        timeout: _timeout,
      );

      testWidgets(
        'save failure surfaces a toast and keeps the form open',
        (tester) async {
          // A controller whose db cannot be opened (the directory does not
          // exist): every write throws, which is exactly the "service will
          // fail" path of the spec. (Closing a drift LazyDatabase does NOT
          // work — it happily re-opens on the next query.)
          final db = EleenDatabase(LazyDatabase(
              () async => NativeDatabase(File('/nonexistent-e2e/x.sqlite3'))));
          final controller = TvController(db: db, speedFactor: 60);

          await tester.pumpWidget(MaterialApp(
            home: ProfileForm(controller: controller),
          ));
          await tester.pump();

          await tester.enterText(
              find.byKey(const Key('profile-form-name')), 'TestKid');
          await tester.pump();
          await tester.tap(find.byKey(const Key('profile-form-save')));
          await pumpFor(tester, const Duration(seconds: 1));

          expect(find.byKey(const Key('profile-form')), findsOneWidget,
              reason: 'form must stay open after a failed save');
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.textContaining('Could not save the profile'),
            ),
            findsOneWidget,
            reason: 'spec: a toast reports the save failure',
          );
        },
        timeout: _timeout,
      );

      testWidgets(
        'a 5 minute daily allowance works end to end: create, picker, '
        'persist, expire',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('add-profile-card')),
            const Duration(seconds: 60),
            context: 'picker',
          );

          // The create form offers the 5-minute chip alongside the others.
          await tester.tap(find.byKey(const Key('add-profile-card')));
          await waitForFound(
            tester,
            find.byKey(const Key('parent-pin-prompt')),
            const Duration(seconds: 15),
          );
          await tapPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('profile-form')),
            const Duration(seconds: 15),
            context: 'create form',
          );
          for (final minutes in [5, 15, 30, 45, 60]) {
            expect(find.byKey(Key('profile-form-allowance-$minutes')),
                findsOneWidget,
                reason: 'the $minutes-minute chip must be offered');
          }

          await tester.enterText(
              find.byKey(const Key('profile-form-name')), 'QuickKid');
          await tester.pump();
          await tester.tap(find.byKey(const Key('profile-form-allowance-5')));
          await pumpFor(tester, const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const Key('profile-form-save')));

          // The picker card carries the 5-minute allowance.
          await waitForFound(
            tester,
            find.textContaining('Remaining 5m 00s'),
            const Duration(seconds: 30),
            context: 'picker with the 5-minute profile',
          );
          final db = await openDeviceTvDb();
          final profiles = await db.allProfiles();
          await db.close();
          final quick = profiles.where((p) => p.name == 'QuickKid').single;
          expect(quick.allowance.minutes, 5);

          // The short session runs out quickly at ELEN_FAST (5 wall seconds).
          // Wait the form route fully out first: its name field still holds
          // the "QuickKid" text mid-animation and would make the tap ambiguous.
          await waitForGone(
            tester,
            find.byKey(const Key('profile-form')),
            const Duration(seconds: 15),
          );
          // Enforcing the new profile is PIN-gated (a parent PIN is set):
          // tap the card, clear the gate, then the session runs in the
          // background until the 5-minute allowance expires into the lock.
          await tester.tap(find.text('QuickKid'));
          await waitForFound(
            tester,
            find.byKey(const Key('parent-pin-prompt')),
            const Duration(seconds: 15),
            context: 'enforcement PIN gate for the new profile',
          );
          await tapPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 30),
            context: 'lock overlay after the 5-minute allowance runs out',
          );
          expect(find.text("Time's up!"), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'the form is child-only: no parent toggle, allowance chips always up',
        (tester) async {
          await openCreateForm(tester);
          expect(find.byKey(const Key('profile-form-parent-toggle')),
              findsNothing);
          expect(find.byKey(const Key('profile-form-allowance-15')),
              findsOneWidget);
          expect(find.byKey(const Key('profile-form-allowance-60')),
              findsOneWidget);
        },
        timeout: _timeout,
      );
    });

    // ------------------------------------------- profile_switching_pin
    group('profile_switching_pin.feature', () {
      Future<void> openPinSettings(WidgetTester tester) async {
        await waitForFound(
          tester,
          find.byKey(const Key('settings-pin')),
          const Duration(seconds: 60),
          context: 'TV home settings row',
        );
        await tester.tap(find.byKey(const Key('settings-pin')));
        await waitForFound(
          tester,
          find.byKey(const Key('pin-settings')),
          const Duration(seconds: 15),
          context: 'PIN settings sheet',
        );
      }

      testWidgets(
        'set flow: PIN shorter than 4 digits is rejected',
        (tester) async {
          await seedDeviceTvDb(parentPin: '');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);

          // No PIN set: straight into the set flow.
          await waitForFound(
            tester,
            find.text('Set a parent PIN'),
            const Duration(seconds: 15),
          );
          await tapPin(tester, '123');
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.text('Use at least 4 digits'), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'set flow: the pad accepts at most 4 digits',
        (tester) async {
          await seedDeviceTvDb(parentPin: '');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(
            tester,
            find.text('Set a parent PIN'),
            const Duration(seconds: 15),
          );
          await tapPin(tester, '12345');
          await pumpFor(tester, const Duration(milliseconds: 300));
          expect(find.text('•••••'), findsNothing,
              reason: 'spec: PIN is exactly 4 digits; the 5th is ignored');
          expect(find.text('••••'), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'set flow: mismatched confirmation shows an error',
        (tester) async {
          await seedDeviceTvDb(parentPin: '');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(
              tester, find.text('Set a parent PIN'), const Duration(seconds: 15));
          await tapPin(tester, '1234');
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await waitForFound(
              tester, find.text('Confirm the new PIN'), const Duration(seconds: 5));
          await tapPin(tester, '4321');
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.text('PINs do not match'), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'change flow: wrong current PIN is rejected with "Wrong PIN"',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(
              tester, find.byKey(const Key('pin-settings-change')),
              const Duration(seconds: 15));
          await tester.tap(find.byKey(const Key('pin-settings-change')));
          await waitForFound(
              tester, find.text('Enter the current PIN'), const Duration(seconds: 5));
          await tapPin(tester, '000000');
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.text('Wrong PIN'), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'remove PIN: enforcement toggles are no longer gated',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(
              tester, find.byKey(const Key('pin-settings-remove')),
              const Duration(seconds: 15));
          await tester.tap(find.byKey(const Key('pin-settings-remove')));
          await waitForFound(
              tester,
              find.text('Enter the current PIN to remove it'),
              const Duration(seconds: 5));
          await tapPin(tester, e2eParentPin);
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await waitForFound(tester, find.text('PIN removed'),
              const Duration(seconds: 15));
          await tester.tap(find.byKey(const Key('pin-settings-done')));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 30),
            context: 'picker after removing the PIN',
          );
          // The settings route is still sliding out; wait for it to finish so
          // the picker is not mid-transition (its cells would be off-screen).
          await waitForGone(
            tester,
            find.byKey(const Key('pin-settings')),
            const Duration(seconds: 15),
          );

          // With no PIN set, the enforcement toggle is ungated: flipping it
          // starts the session directly.
          await tester.tap(find.byKey(const Key('profile-toggle-e2e-kid')));
          await waitForFound(
            tester,
            find.byKey(const Key('enforced-remaining')),
            const Duration(seconds: 15),
            context: 'enforcement started without a PIN gate',
          );
          expect(find.byKey(const Key('parent-pin-prompt')), findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'with a PIN set, enabling enforcement from the toggle is gated',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-toggle-e2e-kid')),
            const Duration(seconds: 60),
            context: 'picker',
          );

          await tester.tap(find.byKey(const Key('profile-toggle-e2e-kid')));
          await waitForFound(
            tester,
            find.byKey(const Key('parent-pin-prompt')),
            const Duration(seconds: 15),
            context: 'toggle PIN gate',
          );
          // No session starts behind the prompt.
          expect(find.byKey(const Key('enforced-remaining')), findsNothing);

          // A wrong PIN keeps the gate closed.
          await tapPin(tester, '0000');
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.byKey(const Key('pin-error')), findsOneWidget);
          expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);

          // The correct PIN starts enforcement.
          await tapPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('enforced-remaining')),
            const Duration(seconds: 15),
            context: 'enforcement started after the correct PIN',
          );
        },
        timeout: _timeout,
      );

      testWidgets(
        'no PIN set: no change/remove options are offered',
        (tester) async {
          await seedDeviceTvDb(parentPin: '');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);

          // No PIN set: straight into the set flow — the menu (with its
          // Change/Remove options) never appears.
          await waitForFound(
            tester,
            find.text('Set a parent PIN'),
            const Duration(seconds: 15),
            context: 'set flow with no PIN set',
          );
          expect(find.byKey(const Key('pin-settings-change')), findsNothing);
          expect(find.byKey(const Key('pin-settings-remove')), findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'remove PIN with a wrong current PIN is rejected',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(tester, find.byKey(const Key('pin-settings-remove')),
              const Duration(seconds: 15));
          await tester.tap(find.byKey(const Key('pin-settings-remove')));
          await waitForFound(
              tester,
              find.text('Enter the current PIN to remove it'),
              const Duration(seconds: 5));
          await tapPin(tester, '000000');
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await pumpFor(tester, const Duration(milliseconds: 500));

          expect(find.text('Wrong PIN'), findsOneWidget);
          // The PIN is still set: the option row never leaves.
          expect(find.byKey(const Key('pin-settings-next')), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'a 5-digit new PIN is rejected with "Use no more than 4 digits"',
        (tester) async {
          await seedDeviceTvDb(parentPin: '');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(
              tester, find.text('Set a parent PIN'), const Duration(seconds: 15));
          await tapPin(tester, '12345');
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.text('Use no more than 4 digits'), findsOneWidget,
              reason: 'spec: PINs are exactly 4 digits');
        },
        timeout: _timeout,
      );

      testWidgets(
        'changing the PIN to the same value is rejected',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(tester, find.byKey(const Key('pin-settings-change')),
              const Duration(seconds: 15));
          await tester.tap(find.byKey(const Key('pin-settings-change')));
          await waitForFound(
              tester, find.text('Enter the current PIN'), const Duration(seconds: 5));
          await tapPin(tester, e2eParentPin);
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await waitForFound(
              tester, find.text('Enter the new PIN'), const Duration(seconds: 5));
          await tapPin(tester, e2eParentPin);
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(
            find.textContaining('different from the current PIN'),
            findsOneWidget,
            reason: 'spec: a no-op PIN change must be rejected',
          );
        },
        timeout: _timeout,
      );

      testWidgets(
        'a legacy longer-than-4-digit PIN can still be matched in the '
        'change flow',
        (tester) async {
          // A pre-exactly-4 database may hold a longer PIN; the current-PIN
          // stage must accept it (cap at the stored length) or the owner is
          // locked out of Change/Remove forever.
          await seedDeviceTvDb(parentPin: '123456');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await openPinSettings(tester);
          await waitForFound(tester, find.byKey(const Key('pin-settings-change')),
              const Duration(seconds: 15));
          await tester.tap(find.byKey(const Key('pin-settings-change')));
          await waitForFound(
              tester, find.text('Enter the current PIN'), const Duration(seconds: 5));
          await tapPin(tester, '123456');
          await tester.tap(find.byKey(const Key('pin-settings-next')));
          await waitForFound(
            tester,
            find.text('Enter the new PIN'),
            const Duration(seconds: 5),
            context: 'change flow accepts a legacy 6-digit current PIN',
          );
          // Back out without saving.
          await tester.tap(find.byKey(const Key('pin-settings-cancel')));
          await pumpFor(tester, const Duration(milliseconds: 500));
        },
        timeout: _timeout,
      );
    });

    // ------------------------------------------------- enforcement_home
    group('enforcement_home.feature', () {
      testWidgets(
        'enabling enforcement keeps the home and shows the status row',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);

          // The home is still the main screen: the picker + settings row stay
          // up, with the compact status row on top (no countdown screen and
          // no dashboard).
          expect(find.byKey(const Key('profile-card-e2e-kid')), findsOneWidget);
          expect(find.byKey(const Key('add-profile-card')), findsOneWidget);
          expect(find.byKey(const Key('settings-pin')), findsOneWidget);
          expect(find.byKey(const Key('enforced-remaining')), findsOneWidget);
          expect(find.byKey(const Key('countdown-compact')), findsOneWidget);
          expect(find.byKey(const Key('countdown-dashboard')), findsNothing);
          expect(find.byKey(const Key('countdown-home')), findsNothing);
          // The pill carries the wall-clock time.
          expect(
            find.descendant(
              of: find.byKey(const Key('countdown-compact')),
              matching: find.textContaining(RegExp(r'^\d{1,2}:\d{2} [AP]M$')),
            ),
            findsOneWidget,
            reason: 'the compact pill carries the wall-clock time',
          );
        },
        timeout: _timeout,
      );

      testWidgets(
        'the overlay permission status chip is shown on the home',
        (tester) async {
          // run_e2e.sh keeps the permission granted, so the chip reads
          // "allowed" and never raises the banner (the revoked/red variant
          // is a @real-device scenario).
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await waitForFound(
            tester,
            find.byKey(const Key('overlay-permission-status-granted')),
            const Duration(seconds: 30),
            context: 'permission status chip in the settings row',
          );
          expect(find.byKey(const Key('overlay-permission-status')),
              findsOneWidget);
          expect(find.byKey(const Key('overlay-permission-banner')),
              findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'the compact pill shows the current wall-clock time',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);

          String clockFromPill() => tester.widget<Text>(find.descendant(
                of: find.byKey(const Key('countdown-compact')),
                matching: find.byType(Text),
              ).first).data!;

          // The pill matches the device clock (hour and minute agree with
          // DateTime.now(); the pill may be one minute ahead of the read
          // if the clock ticks in between).
          final now = DateTime.now();
          final pill = clockFromPill();
          expect(pill, matches(RegExp(r'^\d{1,2}:\d{2} [AP]M$')));
          final parts = pill.split(' '); // "8:45", "PM"
          final hm = parts[0].split(':');
          final pillHour12 = int.parse(hm[0]) % 12;
          final pillMinute = int.parse(hm[1]);
          expect(parts[1], now.hour < 12 ? 'AM' : 'PM');
          expect(pillHour12, now.hour % 12);
          expect((pillMinute - now.minute) % 60, anyOf(0, 1));
        },
        timeout: _timeout,
      );

      testWidgets(
        'the last-minute badge appears in the final minute, then the lock',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);

          // Play to the final scaled minute: the badge mounts in the status
          // row alongside the live remaining, still before the lock.
          await waitForFound(
            tester,
            find.byKey(const Key('last-minute-countdown')),
            const Duration(seconds: 45),
            context: 'last-minute badge',
          );
          expect(find.byKey(const Key('enforced-remaining')), findsOneWidget);
          expect(find.byKey(const Key('countdown-compact')), findsOneWidget);
          expect(find.byKey(const Key('lock-overlay')), findsNothing);

          // It ends in expiry.
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 20),
            context: 'lock overlay after the last minute',
          );
          expect(find.text("Time's up!"), findsOneWidget);
        },
        timeout: _timeout,
      );
    });

    // --------------------------------------------------- times_up_screen
    group('times_up_screen.feature', () {
      testWidgets(
        'lock overlay persists until a parent action',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          // Nothing happens on its own: no chooser, no countdown, overlay
          // stays for several seconds of wall time.
          await pumpFor(tester, const Duration(seconds: 3));
          expect(find.byKey(const Key('lock-overlay')), findsOneWidget);
          expect(find.byKey(const Key('unlock-15')), findsNothing);
          expect(find.text("Time's up!"), findsOneWidget);

          // The PIN gate still works after the wait.
          await tapPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-15')),
            const Duration(seconds: 15),
            context: 'chooser after waiting',
          );
        },
        timeout: _timeout,
      );

      testWidgets(
        'lock overlay closes after adding time; countdown resumes at 15:00',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          await tapPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-15')),
            const Duration(seconds: 15),
            context: 'chooser after PIN',
          );
          await tester.tap(find.byKey(const Key('unlock-15')));

          await waitForGone(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 30),
          );
          expect(find.text("Time's up!"), findsNothing);
          await waitForFound(tester, countdownTextFinder,
              const Duration(seconds: 15),
              context: 'countdown after add 15');
          expect(remainingFromUi(tester), inInclusiveRange(780, 900));
        },
        timeout: _timeout,
      );

      testWidgets(
        'the lock screen shows a Switch profile button; it is PIN-guarded',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          // The button is visible right on the Time's up screen, next to
          // the pad — no PIN entered yet.
          expect(find.byKey(const Key('lock-switch-direct')), findsOneWidget);
          expect(find.text('Switch profile'), findsOneWidget);

          // It is a parent action: with a PIN set, tapping it asks for the
          // PIN instead of switching.
          await tester.tap(find.byKey(const Key('lock-switch-direct')));
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.byKey(const Key('pin-error')), findsOneWidget);
          expect(find.textContaining('Enter the parent PIN first'),
              findsOneWidget);
          expect(find.byKey(const Key('lock-overlay')), findsOneWidget);

          // The correct PIN still leads to the chooser with the real switch.
          await tapPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-switch')),
            const Duration(seconds: 15),
            context: 'chooser after PIN',
          );
          await tester.tap(find.byKey(const Key('unlock-switch')));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 15),
            context: 'picker after switch',
          );
          expect(find.byKey(const Key('lock-overlay')), findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'lock overlay closes after switching profile; picker shows',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          await tapPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-switch')),
            const Duration(seconds: 15),
            context: 'chooser with Switch profile',
          );
          await tester.tap(find.byKey(const Key('unlock-switch')));

          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 15),
            context: 'picker after switch',
          );
          expect(find.text("Time's up!"), findsNothing);
          expect(find.byKey(const Key('lock-overlay')), findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'no PIN set: switch profile is available without a PIN',
        (tester) async {
          await seedDeviceTvDb(parentPin: '');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          // The chooser offers Switch profile straight away — no PIN pad.
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-switch')),
            const Duration(seconds: 15),
            context: 'switch affordance with no PIN set',
          );
          expect(find.byKey(const Key('pin-pad')), findsNothing);
          await tester.tap(find.byKey(const Key('unlock-switch')));

          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 15),
            context: 'picker after switch with no PIN',
          );
          expect(find.byKey(const Key('lock-overlay')), findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'wrong PIN on the lock overlay is rejected, chooser stays hidden',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          await tapPin(tester, '000000');
          await pumpFor(tester, const Duration(milliseconds: 500));
          expect(find.byKey(const Key('pin-error')), findsOneWidget);
          expect(find.byKey(const Key('unlock-15')), findsNothing);
          expect(find.byKey(const Key('lock-overlay')), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'no PIN set: the overlay offers add time without asking for a PIN',
        (tester) async {
          await seedDeviceTvDb(parentPin: '');
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          // The chooser is offered straight away — no PIN pad gate.
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-15')),
            const Duration(seconds: 15),
            context: 'add-time chooser with no PIN set',
          );
          expect(find.byKey(const Key('pin-pad')), findsNothing);

          await tester.tap(find.byKey(const Key('unlock-15')));
          await waitForGone(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 30),
          );
        },
        timeout: _timeout,
      );

      testWidgets(
        'PIN pad is fully D-pad navigable on the lock overlay',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester.pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          // The pad takes focus on its own — no pointer needed.
          await waitForFound(
            tester,
            find.byKey(const Key('pin-pad')),
            const Duration(seconds: 15),
          );
          expect(focusedLabel(), isNotNull,
              reason: 'a pin key must hold focus for the D-pad');

          // Enter the 4-digit PIN (e2eParentPin) with arrows + Select only.
          // Grid is 1-2-3 / 4-5-6 / 7-8-9 / 0; focus starts on '1'. Path:
          // 1, right->2, right->3, down->6? no — down from 3 is 6; to reach
          // 4 go down-left-left, then Select on 4 completes the PIN.
          Future<void> key(LogicalKeyboardKey k) async {
            await tester.sendKeyEvent(k);
            await pumpFor(tester, const Duration(milliseconds: 150));
          }

          await key(LogicalKeyboardKey.select); // 1
          await key(LogicalKeyboardKey.arrowRight);
          await key(LogicalKeyboardKey.select); // 2
          await key(LogicalKeyboardKey.arrowRight);
          await key(LogicalKeyboardKey.select); // 3
          await key(LogicalKeyboardKey.arrowDown);
          await key(LogicalKeyboardKey.arrowLeft);
          await key(LogicalKeyboardKey.arrowLeft);
          await key(LogicalKeyboardKey.select); // 4 — PIN '1234' complete

          await waitForFound(
            tester,
            find.byKey(const Key('unlock-15')),
            const Duration(seconds: 15),
            context: 'chooser after D-pad-only PIN entry',
          );
        },
        timeout: _timeout,
      );
    });
  }

  if (runPhoneScenarios) {
    // ----------------------------------------- phone_pairing_dashboard
    group('phone_pairing_dashboard.feature', () {
      late PhoneTestTv tv;

      setUp(() async {
        await clearPhonePairing();
        tv = PhoneTestTv();
        await tv.start();
        await tv.seed(parentPin: e2eParentPin);
      });

      tearDown(() async {
        await tv.stop();
      });

      testWidgets(
        'unpaired home shows the not-paired status and Scan TV code',
        (tester) async {
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await waitForFound(
            tester,
            find.text('Scan TV code'),
            const Duration(seconds: 30),
            context: 'unpaired phone home',
          );
          expect(find.byIcon(Icons.tv_off), findsOneWidget,
              reason: 'not-paired status icon');
          expect(find.byKey(const Key('open-dashboard')), findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'paired home shows the paired status and Open Dashboard',
        (tester) async {
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await pairViaManualCode(tester, tv);
          expect(find.byIcon(Icons.tv), findsOneWidget,
              reason: 'paired status icon');
          expect(find.byKey(const Key('open-dashboard')), findsOneWidget);
          expect(find.textContaining('Paired to 127.0.0.1'), findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'the dashboard warns while the TV reports its overlay permission '
        'denied, and clears once granted',
        (tester) async {
          // The TV publishes its SYSTEM_ALERT_WINDOW probe result with the
          // state; the test headless TV flips the flag the way a denied
          // probe would (the real red chip is a @real-device scenario).
          tv.coordinator.overlayPermissionGranted = false;

          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await pairViaManualCode(tester, tv);
          await openDashboard(tester);
          await waitForFound(
            tester,
            find.byKey(const Key('tv-overlay-permission-denied')),
            const Duration(seconds: 30),
            context: 'dashboard warning while the TV permission is denied',
          );
          expect(find.textContaining("can't lock other apps"), findsOneWidget);

          // Granted on the TV: the next refresh clears the warning.
          tv.coordinator.overlayPermissionGranted = true;
          await tester.tap(find.text('Add time'));
          await submitPin(tester, e2eParentPin);
          await waitForGone(
            tester,
            find.byKey(const Key('tv-overlay-permission-denied')),
            const Duration(seconds: 30),
          );
          expect(find.byKey(const Key('tv-overlay-permission-allowed')),
              findsOneWidget);
        },
        timeout: _timeout,
      );

      testWidgets(
        'pairing survives an app relaunch',
        (tester) async {
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await pairViaManualCode(tester, tv);

          await unmountApp(tester);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));

          await waitForFound(
            tester,
            find.byKey(const Key('open-dashboard')),
            const Duration(seconds: 30),
            context: 'paired home after relaunch',
          );
          expect(find.byIcon(Icons.tv), findsOneWidget);
          // "Scan TV code" stays visible by design (the re-pair affordance
          // is always offered); only its status icon changes.
        },
        timeout: _timeout,
      );

      testWidgets(
        'the server rejects a 5-digit PIN from an API client',
        (tester) async {
          // Defense in depth: the shipped UI caps the field at 4, but a
          // bearer-token client must not be able to persist a longer PIN
          // either.
          await tv.db.saveSettings(
              Settings(parentPin: e2eParentPin, token: e2ePairToken));
          final client = EleenClient(
            base: Uri.parse('http://127.0.0.1:${tv.server.port}'),
            token: e2ePairToken,
          );

          await expectLater(
            client.setPin('12345'),
            throwsA(isA<EleenApiError>()),
            reason: 'PUT /api/pin must enforce exactly 4 digits',
          );
          final settings = await tv.db.getSettings();
          expect(settings.parentPin, e2eParentPin,
              reason: 'a rejected PIN must not be persisted');
        },
        timeout: _timeout,
      );
    });
  }
}
