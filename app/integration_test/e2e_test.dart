// Eleen end-to-end scenarios (Tasks 1-13 features working together).
//
// Runs on a live emulator (`eleen_tv` AVD) with
// `--dart-define=ELEN_FAST=1`: speedFactor 60 makes a 15-minute allowance
// expire in ~15 wall seconds and the 10/5-minute reminder toasts fire ~5s
// and ~10s into a run.
//
// Scenario form factors are selected by `ELEEN_FORM` (tv|phone|all, default
// all); every scenario pumps the production `EleenApp` (see the harness
// header for the full single-device design).
//
//   TV pass:    flutter test integration_test/e2e_test.dart \
//                 --dart-define=ELEN_FAST=1 --dart-define=ELEEN_FORM=tv -d eleen_tv
//   Phone pass: flutter test integration_test/e2e_test.dart \
//                 --dart-define=ELEN_FAST=1 --dart-define=ELEEN_FORM=phone -d eleen_tv
//   All six:    same command without ELEEN_FORM.
//
// Not E2E-verifiable in an emulator (real-device checklist, per plan): the
// SYSTEM_ALERT_WINDOW overlay render and real camera QR scanning.

import 'dart:async';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:eleen/phone/profiles_screen.dart';
import 'package:eleen/state/phone_controller.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/tv_harness.dart';

const _timeout = Timeout(Duration(minutes: 4));

void main() {
  ensureE2eBinding();

  // ---------------------------------------------------------------- TV pass
  if (runTvScenarios) {
    group('TV (production bootstrap over the seeded device db)', () {
      testWidgets(
        'scenario 1: seed -> picker -> session runs -> expires -> overlay -> '
        'PIN add 15 -> overlay clears',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
            context: 'picker with seeded profile',
          );

          // The permission status chip reflects the run's granted overlay
          // permission (run_e2e.sh keeps SYSTEM_ALERT_WINDOW allowed).
          await waitForFound(
            tester,
            find.byKey(const Key('overlay-permission-status-granted')),
            const Duration(seconds: 30),
            context: 'overlay permission chip on an idle picker',
          );
          expect(find.byKey(const Key('overlay-permission-banner')),
              findsNothing,
              reason: 'granted permission must not raise the banner');

          // Session starts at (or one tick under) the full 15-minute
          // allowance.
          await selectProfileOnTv(tester);
          expect(remainingFromUi(tester), inInclusiveRange(780, 900));

          // ~15 wall seconds at speedFactor 60 to play it down to zero.
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );
          expect(find.text("Time's up!"), findsOneWidget);

          // Parent PIN on the D-pad pad, then add 15 minutes.
          for (final digit in e2eParentPin.split('')) {
            await tester.tap(find.byKey(Key('pin-key-$digit')));
            await pumpFor(tester, const Duration(milliseconds: 120));
          }
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-15')),
            const Duration(seconds: 15),
            context: 'add-time chooser after correct PIN',
          );
          await tester.tap(find.byKey(const Key('unlock-15')));

          // Overlay clears and the countdown resumes at the full allowance.
          await waitForGone(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 30),
          );
          expect(find.text("Time's up!"), findsNothing);
          await waitForFound(tester, countdownTextFinder,
              const Duration(seconds: 15),
              context: 'countdown after add 15');
          final remaining = remainingFromUi(tester);
          expect(remaining, isNotNull);
          expect(remaining!, inInclusiveRange(780, 900),
              reason: 'back at (or one tick under) 15:00');
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 5: relaunch mid-session -> remaining persisted and resumed',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);

          // Run a few wall seconds so a meaningful remainder is persisted.
          await pumpFor(tester, const Duration(seconds: 3));
          final beforeRelaunch = remainingFromUi(tester);
          expect(beforeRelaunch, isNotNull);
          expect(beforeRelaunch, lessThan(900));

          // Relaunch: unmount the app (disposing the production controller
          // and closing its db), then build the production app again — a new
          // TvController re-opens the db like a fresh process start. (An OS
          // process restart is not possible inside integration_test; this is
          // the same state reload path, short of the OS.)
          await unmountApp(tester);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));

          // The picker is skipped: today's session is still active, so the
          // countdown resumes at the persisted remainder (a fresh controller
          // consumes no idle time — its tick baseline starts at construction).
          await waitForFound(
            tester,
            countdownTextFinder,
            const Duration(seconds: 60),
            context: 'countdown after relaunch',
          );
          final afterRelaunch = remainingFromUi(tester);
          expect(afterRelaunch, isNotNull);
          expect(afterRelaunch!, lessThanOrEqualTo(beforeRelaunch!));
          expect(beforeRelaunch - afterRelaunch, lessThanOrEqualTo(240),
              reason: 'relaunch must not consume more than a couple of ticks');
          expect(afterRelaunch, greaterThan(0));

          // And the resumed session keeps burning time.
          await pumpFor(tester, const Duration(seconds: 3));
          final afterResume = remainingFromUi(tester);
          expect(afterResume, isNotNull);
          expect(afterResume!, lessThan(afterRelaunch));
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 6: toasts at scaled 10/5 minutes; last-minute countdown in '
        'the final scaled minute',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);

          // Poll the UI through the whole run, recording the order in which
          // the 10- and 5-minute toasts appear (speedFactor 60: ~5s and ~10s
          // in). The 15-minute threshold cannot fire (it is not below the
          // session start).
          final seen = <String>[];
          final deadlines = <String, DateTime>{};
          DateTime now() => DateTime.now();
          deadlines['10 minutes left'] = now().add(const Duration(seconds: 25));
          deadlines['5 minutes left'] = now().add(const Duration(seconds: 45));
          bool seenToast(String message) => find
              .descendant(
                of: find.byKey(const Key('reminder-toast')),
                matching: find.text(message),
              )
              .evaluate()
              .isNotEmpty;

          while (find
                  .byKey(const Key('last-minute-countdown'))
                  .evaluate()
                  .isEmpty &&
              now().isBefore(deadlines['5 minutes left']!)) {
            for (final message in const ['10 minutes left', '5 minutes left']) {
              if (!seen.contains(message) &&
                  seenToast(message) &&
                  now().isBefore(deadlines[message]!)) {
                seen.add(message);
              }
            }
            await pumpFor(tester, const Duration(milliseconds: 200));
          }
          expect(seen, const ['10 minutes left', '5 minutes left'],
              reason: 'both reminder toasts fire, in order, at scaled times');

          // Final scaled minute: the per-second badge is up, still above the
          // lock overlay.
          await waitForFound(
            tester,
            find.byKey(const Key('last-minute-countdown')),
            const Duration(seconds: 20),
            context: 'last-minute countdown badge',
          );
          expect(find.byKey(const Key('lock-overlay')), findsNothing);

          // It ends in expiry.
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 20),
            context: 'lock overlay after last minute',
          );
          expect(find.text("Time's up!"), findsOneWidget);
        },
        timeout: _timeout,
      );
      testWidgets(
        'scenario 7: enforcement is PIN gated and the home status row is the '
        'only session surface',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-toggle-e2e-kid')),
            const Duration(seconds: 60),
            context: 'picker with the enforcement toggle',
          );

          // Toggling enforcement demands the PIN before any session starts.
          await tester.tap(find.byKey(const Key('profile-toggle-e2e-kid')));
          await waitForFound(
            tester,
            find.byKey(const Key('parent-pin-prompt')),
            const Duration(seconds: 15),
            context: 'enforcement PIN prompt',
          );
          expect(find.byKey(const Key('enforced-remaining')), findsNothing);

          // A wrong PIN is rejected: error shown, prompt stays, no session.
          for (final digit in '0000'.split('')) {
            await tester.tap(find.byKey(Key('pin-key-$digit')));
            await pumpFor(tester, const Duration(milliseconds: 120));
          }
          await pumpFor(tester, const Duration(milliseconds: 300));
          expect(find.byKey(const Key('pin-error')), findsOneWidget);
          expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);

          // The correct PIN starts enforcement: the home keeps its picker and
          // shows the status row (no countdown screen).
          for (final digit in e2eParentPin.split('')) {
            await tester.tap(find.byKey(Key('pin-key-$digit')));
            await pumpFor(tester, const Duration(milliseconds: 120));
          }
          await waitForFound(
            tester,
            find.byKey(const Key('enforced-remaining')),
            const Duration(seconds: 15),
            context: 'status row after correct PIN',
          );
          expect(find.byKey(const Key('profile-card-e2e-kid')), findsOneWidget);
          expect(find.byKey(const Key('settings-pin')), findsOneWidget);
          expect(find.byKey(const Key('countdown-dashboard')), findsNothing);
          expect(remainingFromUi(tester), inInclusiveRange(780, 900));
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 8: TV profile management — add card -> PIN -> create '
        'TestKid -> long-press edit -> 15 min -> picker + server reflect',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
            context: 'picker with seeded profile',
          );
          expect(find.byKey(const Key('add-profile-card')), findsOneWidget);

          // The add card is PIN-gated: wrong PIN shows the error, no form.
          await tester.tap(find.byKey(const Key('add-profile-card')));
          await waitForFound(
            tester,
            find.byKey(const Key('parent-pin-prompt')),
            const Duration(seconds: 15),
            context: 'create-form PIN gate',
          );
          for (final digit in '0000'.split('')) {
            await tester.tap(find.byKey(Key('pin-key-$digit')));
            await pumpFor(tester, const Duration(milliseconds: 120));
          }
          await pumpFor(tester, const Duration(milliseconds: 300));
          expect(find.byKey(const Key('pin-error')), findsOneWidget);
          expect(find.byKey(const Key('profile-form')), findsNothing);

          // The correct PIN opens the create form.
          for (final digit in e2eParentPin.split('')) {
            await tester.tap(find.byKey(Key('pin-key-$digit')));
            await pumpFor(tester, const Duration(milliseconds: 120));
          }
          await waitForFound(
            tester,
            find.byKey(const Key('profile-form')),
            const Duration(seconds: 15),
            context: 'create form after correct PIN',
          );

          // Fill the form: name + default 30-minute allowance, save.
          await tester.enterText(
              find.byKey(const Key('profile-form-name')), 'TestKid');
          await tester.pump();
          await tester.tap(find.byKey(const Key('profile-form-save')));

          // Back on the picker with the new card at its 30-minute allowance.
          await waitForFound(
            tester,
            find.text('TestKid'),
            const Duration(seconds: 30),
            context: 'new profile card on the picker',
          );
          await waitForGone(
            tester,
            find.byKey(const Key('profile-form')),
            const Duration(seconds: 15),
          );
          expect(find.textContaining('Remaining 30m 00s'), findsOneWidget);

          // Long-press edit: PIN, prefilled form, change allowance to 15.
          await tester.longPress(find.text('TestKid'));
          await waitForFound(
            tester,
            find.byKey(const Key('parent-pin-prompt')),
            const Duration(seconds: 15),
            context: 'edit-form PIN gate',
          );
          for (final digit in e2eParentPin.split('')) {
            await tester.tap(find.byKey(Key('pin-key-$digit')));
            await pumpFor(tester, const Duration(milliseconds: 120));
          }
          await waitForFound(
            tester,
            find.byKey(const Key('profile-form')),
            const Duration(seconds: 15),
            context: 'edit form after correct PIN',
          );
          final nameField = tester.widget<TextField>(
            find.byKey(const Key('profile-form-name')),
          );
          expect(nameField.controller!.text, 'TestKid');
          await tester.tap(find.byKey(const Key('profile-form-allowance-15')));
          await pumpFor(tester, const Duration(milliseconds: 200));
          await tester.tap(find.byKey(const Key('profile-form-save')));

          // The picker reflects the edited allowance.
          await waitForFound(
            tester,
            find.textContaining('Remaining 15m 00s'),
            const Duration(seconds: 30),
            context: 'picker after editing allowance to 15 min',
          );
          await waitForGone(
            tester,
            find.byKey(const Key('profile-form')),
            const Duration(seconds: 15),
          );

          // The phone side sees the same server state: read the device db
          // the production TV owns (a second connection, as in scenario 4).
          final db = await openDeviceTvDb();
          final profiles = await db.allProfiles();
          await db.close();
          final kid = profiles.where((p) => p.name == 'TestKid').firstOrNull;
          expect(kid, isNotNull, reason: 'the created profile is persisted');
          expect(kid!.allowance.minutes, 15);
          expect(kid.isParent, isFalse);
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 9: lock screen — slideshow up, PIN, Switch profile -> '
        'picker shows',
        (tester) async {
          await seedDeviceTvDb(parentPin: e2eParentPin);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
            context: 'picker with seeded profile',
          );
          await selectProfileOnTv(tester);

          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );
          expect(find.text("Time's up!"), findsOneWidget);

          // The slideshow is up behind the scrim (scene 0 rendering).
          expect(find.byKey(const Key('lock-scene-0')), findsOneWidget);
          expect(find.byKey(const Key('lock-scrim')), findsOneWidget);
          // The switch-over hint tells a family member what the PIN leads to.
          expect(
            find.text('Enter parent PIN to add time or switch profiles'),
            findsOneWidget,
          );

          // Parent PIN, then the Switch profile affordance.
          for (final digit in e2eParentPin.split('')) {
            await tester.tap(find.byKey(Key('pin-key-$digit')));
            await pumpFor(tester, const Duration(milliseconds: 120));
          }
          await waitForFound(
            tester,
            find.byKey(const Key('unlock-switch')),
            const Duration(seconds: 15),
            context: 'chooser with Switch profile after correct PIN',
          );
          await tester.tap(find.byKey(const Key('unlock-switch')));

          // The expired session ends and the profile picker shows again.
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 15),
            context: 'profile picker after switch',
          );
          expect(find.text("Time's up!"), findsNothing);
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 10: usage records — fast session expires with limitHit '
        'recorded -> relaunch records the shutdown/powerOn pair -> the '
        "phone sees today's usage",
        (tester) async {
          // The seeded token authorizes the phone-side client against the
          // production LAN server this scenario dials later.
          await seedDeviceTvDb(
              parentPin: e2eParentPin, token: e2ePairToken);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('profile-card-e2e-kid')),
            const Duration(seconds: 60),
          );
          await selectProfileOnTv(tester);

          // Play the session down to expiry at ELEN_FAST: every tick books
          // usedSeconds and persists the tick marker.
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay at expiry',
          );

          final today = DateTime.now();
          final db = await openDeviceTvDb();
          final usedAtExpiry = await db.usedSecondsFor('e2e-kid', today);
          expect(usedAtExpiry, greaterThan(0));
          expect(usedAtExpiry, lessThanOrEqualTo(15 * 60),
              reason: 'capped at the 15-minute allowance');
          expect((await db.eventsFor('e2e-kid')).map((e) => e.type),
              [UsageEventType.sessionStart, UsageEventType.limitHit]);
          expect(
              await db.getMetaInt(EleenDatabase.lastTickUptimeMsKey),
              isNotNull);
          await db.close();

          // Relaunch (the production bootstrap re-runs the shutdown
          // recovery): the still-expired session comes back under the lock.
          await unmountApp(tester);
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.tv));
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 60),
            context: 'lock overlay after relaunch',
          );

          // The shutdown -> powerOn pair was recorded, and NO phantom time
          // was invented past the last persisted tick marker.
          final reopened = await openDeviceTvDb();
          final global =
              await reopened.eventsFor(EleenDatabase.appGlobalProfileId);
          expect(global.map((e) => e.type),
              [UsageEventType.shutdown, UsageEventType.powerOn]);
          expect(
              await reopened.usedSecondsFor('e2e-kid', today), usedAtExpiry);
          await reopened.close();

          // The phone dashboard (over the TV's real LAN server) shows the
          // day's usage — pushed over the TV tree so the server stays up.
          final phoneClient = EleenClient(
            base: Uri.parse(
                'http://127.0.0.1:${TvController.defaultServerPort}'),
            token: e2ePairToken,
          );
          // The relaunched server may still be binding: poll briefly.
          final st = await stateWithRetry(phoneClient);
          expect(
              st.usageByProfile['e2e-kid']!.todaySeconds, usedAtExpiry);

          final nav =
              tester.state<NavigatorState>(find.byType(Navigator).first);
          unawaited(nav.push(MaterialPageRoute(
            builder: (_) =>
                ProfilesScreen(client: EleenClientOps(phoneClient)),
          )));
          await waitForFound(
            tester,
            find.byKey(const Key('usage-today-e2e-kid')),
            const Duration(seconds: 30),
            context: "phone row with today's usage line",
          );
          final minutes = (usedAtExpiry / 60).round();
          expect(find.textContaining('Used today: $minutes min'),
              findsOneWidget);
        },
        timeout: _timeout,
      );
    });
  }

  // -------------------------------------------------------------- Phone pass
  if (runPhoneScenarios) {
    group('Phone (real server on device loopback, paired via manual code)',
        () {
      late PhoneTestTv tv;

      setUp(() async {
        await clearPhonePairing();
        tv = PhoneTestTv();
        await tv.start();
        await tv.seed(parentPin: e2eParentPin);
      });

      tearDown(() async {
        // The binding unmounts the previous test's tree (disposing its
        // controllers); stop the test server and close its db.
        await tv.stop();
      });

      testWidgets(
        'scenario 2: manual-code pairing -> profile list shows remaining -> '
        'addTime -> server state increased',
        (tester) async {
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await pairViaManualCode(tester, tv);
          await openDashboard(tester);

          // No session yet: the row mirrors the full 15-minute allowance.
          expect(
            find.textContaining('15:00 left'),
            findsOneWidget,
          );

          // Add time through the PIN-gated picker.
          await tester.tap(find.text('Add time'));
          await submitPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('add-amounts')),
            const Duration(seconds: 15),
            context: 'add-time picker after PIN',
          );
          await tester.tap(find.byKey(const Key('add-amount-15')));

          // The row reflects the new remaining (900 + 900).
          await waitForFound(
            tester,
            find.textContaining('30:00 left'),
            const Duration(seconds: 15),
            context: 'row after add 15',
          );

          // The server is the source of truth.
          final state = await tv.coordinator.state();
          expect(state.remainingByProfile['e2e-kid'], 1800);
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 3: override remaining -> state reflects',
        (tester) async {
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await pairViaManualCode(tester, tv);
          await openDashboard(tester);

          await tester.tap(find.text('Override'));
          await submitPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.byKey(const Key('override-picker')),
            const Duration(seconds: 15),
            context: 'override picker after PIN',
          );
          await tester.tap(find.byKey(const Key('override-minutes-5')));

          await waitForFound(
            tester,
            find.textContaining('5:00 left'),
            const Duration(seconds: 15),
            context: 'row after override to 5 min',
          );

          final state = await tv.coordinator.state();
          expect(state.remainingByProfile['e2e-kid'], 300);
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 4: master lock on -> state.masterLockEnabled + TV shows '
        'overlay; lock off -> remaining preserved',
        (tester) async {
          // A live session so "remaining preserved" is meaningful.
          await tv.seedActiveSession(remainingSeconds: 900);

          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await pairViaManualCode(tester, tv);
          await openDashboard(tester);

          // Lock ON (PIN-gated).
          await tester.tap(find.byKey(const Key('master-lock-switch')));
          await submitPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.textContaining('the TV is locked for every profile'),
            const Duration(seconds: 15),
            context: 'switch subtitle after lock on',
          );
          final locked = await tv.coordinator.state();
          expect(locked.masterLockEnabled, isTrue);
          // The session is deactivated while locked (remaining untouched).
          expect(locked.activeSession, isNull);

          // The production TV home over the same server state shows the
          // master-lock overlay — no PIN pad, no unlock affordance.
          //
          // Unmount first: pumpWidget updates the existing root element in
          // place, so pushed phone routes (dashboard, a just-dismissed PIN
          // dialog still animating out) would leak into the TV tree.
          final tvDb = EleenDatabase(
              LazyDatabase(() async => NativeDatabase(tv.dbFile)));
          final tvController = TvController(db: tvDb, speedFactor: 60);
          await tvController.refresh();
          await unmountApp(tester);
          await tester.pumpWidget(
              EleenApp(formFactor: FormFactor.tv, tvController: tvController));
          await waitForFound(
            tester,
            find.byKey(const Key('lock-overlay')),
            const Duration(seconds: 30),
            context: 'TV lock overlay under master lock',
          );
          expect(find.text('Locked by parent'), findsOneWidget);
          expect(find.byKey(const Key('pin-pad')), findsNothing);
          await unmountApp(tester); // closes only the TV-side connection

          // Back to the phone (pairing persisted) — lock OFF.
          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await waitForFound(
            tester,
            find.byKey(const Key('open-dashboard')),
            const Duration(seconds: 30),
            context: 'paired home after returning from TV view',
          );
          await openDashboard(tester);
          await tester.tap(find.byKey(const Key('master-lock-switch')));
          await submitPin(tester, e2eParentPin);
          await waitForFound(
            tester,
            find.textContaining('profiles can use their allowance'),
            const Duration(seconds: 15),
            context: 'switch subtitle after lock off',
          );

          // The unlocked session is active again with its preserved 15:00.
          final unlocked = await tv.coordinator.state();
          expect(unlocked.masterLockEnabled, isFalse);
          expect(unlocked.activeSession, isNotNull);
          expect(unlocked.activeSession!.active, isTrue);
          expect(unlocked.activeSession!.remainingSeconds, 900);
        },
        timeout: _timeout,
      );

      testWidgets(
        'scenario 5: TV overlay permission denied -> phone dashboard warns; '
        'granted -> warning clears',
        (tester) async {
          // The TV probes SYSTEM_ALERT_WINDOW after every check and
          // publishes the result; the test headless TV flips the flag the
          // way a denied probe would.
          tv.coordinator.overlayPermissionGranted = false;

          await tester
              .pumpWidget(const EleenApp(formFactor: FormFactor.phone));
          await pairViaManualCode(tester, tv);
          await openDashboard(tester);

          // The warning hint mirrors the TV's denial over the real wire.
          await waitForFound(
            tester,
            find.byKey(const Key('tv-overlay-permission-denied')),
            const Duration(seconds: 30),
            context: 'phone hint while the TV permission is denied',
          );
          // The state endpoint really carries the field (dial it as the
          // paired phone would, with the token the pairing stored).
          final prefs = await SharedPreferences.getInstance();
          final denied = await EleenClient(
            base: Uri.parse('http://127.0.0.1:${tv.server.port}'),
            token: prefs.getString('eleen.tv_token'),
          ).state();
          expect(denied.overlayPermissionGranted, isFalse);

          // The TV grants it (e.g. via its settings chip); the next poll
          // clears the hint.
          tv.coordinator.overlayPermissionGranted = true;
          await tester.tap(find.text('Add time')); // any PIN-gated action
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
    });
  }
}
