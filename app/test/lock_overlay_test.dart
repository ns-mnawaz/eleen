
import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/lock_overlay.dart';
import 'package:eleen/tv/overlay_channel.dart';
import 'package:eleen/tv/tv_home.dart';
import 'package:eleen/tv/widgets/lock_slideshow.dart';
import 'package:eleen/tv/widgets/pin_pad.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mutable [Clock]: monotonic time advances only when the test advances it,
/// so ticks are fully deterministic (no real-time sleeps).
class FakeClock implements Clock {
  FakeClock(this.date);

  final DateTime date;
  int _ms = 0;

  void advanceMs(int ms) => _ms += ms;

  @override
  int nowMs() => _ms;

  @override
  DateTime today() => date;
}

/// The debugLabel of the PIN cell currently in the focus path (the pad's
/// cells are wrapped by FocusableActionDetector, so the primary focus node
/// itself is an internal wrapper — the labeled node has focus as its
/// ancestor).
String? focusedDigitLabel(WidgetTester tester) {
  for (final node in tester.binding.focusManager.rootScope.descendants) {
    final label = node.debugLabel;
    if (node.hasFocus && label != null && label.startsWith('pin-key-')) {
      return label;
    }
  }
  return null;
}

void main() {
  group('LockOverlay widget', () {
    Future<void> pumpOverlay(
      WidgetTester tester, {
      String message = "Time's up!",
      bool masterLock = false,
      String pin = '1234',
      required List<int> unlocked,
      PinVerifier? verifyPin,
      VoidCallback? onSwitchProfile,
    }) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          home: LockOverlay(
            message: message,
            masterLock: masterLock,
            loadParentPin: () async => pin,
            verifyPin: verifyPin,
            onUnlock: unlocked.add,
            onSwitchProfile: onSwitchProfile,
          ),
        ),
      );
      await tester.pump();
    }

    /// Enters [digits] by tapping the corresponding PIN pad cells.
    Future<void> enterDigits(WidgetTester tester, List<String> digits) async {
      for (final digit in digits) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pump();
      }
    }

    testWidgets('covers the full MediaQuery size', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(2000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final unlocked = <int>[];
      await pumpOverlay(tester, unlocked: unlocked);

      expect(
        tester.getSize(find.byKey(const Key('lock-overlay'))),
        const Size(2000, 1200),
      );
      expect(find.byType(PinPad), findsOneWidget);
    });

    testWidgets('pin pad focus traverses 1-9 then 0 in order', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, unlocked: unlocked);

      // The first cell ('1') has autofocus, so the D-pad starts there.
      final visited = <String>[];
      for (var i = 0; i < 10; i++) {
        visited.add(focusedDigitLabel(tester)!);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        // Focus traversal settles on the following frame.
        await tester.pump();
      }
      expect(visited, [for (var d = 1; d <= 9; d++) 'pin-key-$d', 'pin-key-0']);
    });

    testWidgets('d-pad arrows move focus across the grid', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, unlocked: unlocked);

      // Autofocus is on '1'.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(focusedDigitLabel(tester), 'pin-key-2');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedDigitLabel(tester), 'pin-key-5');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedDigitLabel(tester), 'pin-key-2');
    });

    testWidgets('wrong PIN shows an error and the overlay stays', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, pin: '1234', unlocked: unlocked);

      // No feedback until the entry reaches the PIN's full length...
      await enterDigits(tester, ['1', '2', '3']);
      expect(find.byKey(const Key('pin-error')), findsNothing);

      // ... '1-2-3-9' is a complete but wrong attempt: error, overlay stays.
      await enterDigits(tester, ['9']);
      expect(find.byKey(const Key('pin-error')), findsOneWidget);
      expect(find.text('Wrong PIN'), findsOneWidget);
      // The overlay stays: the pad is still there and nothing unlocked.
      expect(find.byType(PinPad), findsOneWidget);
      expect(unlocked, isEmpty);
    });

    testWidgets('correct PIN shows the chooser and reports 15 minutes', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, pin: '1234', unlocked: unlocked);

      await enterDigits(tester, ['1', '2', '3', '4']);
      await tester.pump();
      expect(find.byKey(const Key('pin-error')), findsNothing);
      expect(find.byKey(const Key('unlock-15')), findsOneWidget);
      expect(find.byKey(const Key('unlock-30')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unlock-15')));
      await tester.pump();
      expect(unlocked, [15]);
    });

    testWidgets('correct PIN + 30 reports 30 minutes', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, pin: '1234', unlocked: unlocked);

      await enterDigits(tester, ['1', '2', '3', '4']);
      await tester.pump();
      await tester.tap(find.byKey(const Key('unlock-30')));
      await tester.pump();
      expect(unlocked, [30]);
    });

    testWidgets(
      'correct PIN offers Switch profile, which switches without unlocking',
      (WidgetTester tester) async {
        final unlocked = <int>[];
        var switched = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: LockOverlay(
              message: "Time's up!",
              loadParentPin: () async => '1234',
              onUnlock: unlocked.add,
              onSwitchProfile: () => switched++,
            ),
          ),
        );
        await tester.pump();

        await enterDigits(tester, ['1', '2', '3', '4']);
        await tester.pump();
        expect(find.byKey(const Key('unlock-switch')), findsOneWidget);

        // D-pad operable: Tab past the two time buttons, Enter activates.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(switched, 1);
        expect(unlocked, isEmpty);
      },
    );

    testWidgets(
      'chooser is D-pad operable: autofocus + activation reports 15',
      (WidgetTester tester) async {
        final unlocked = <int>[];
        await pumpOverlay(tester, pin: '1234', unlocked: unlocked);

        await enterDigits(tester, ['1', '2', '3', '4']);
        await tester.pump();
        // The 'Add 15 minutes' button takes focus as soon as the pad unmounts.
        expect(find.byKey(const Key('pin-pad')), findsNothing);
        expect(focusedDigitLabel(tester), isNull);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(unlocked, [15]);
      },
    );

    testWidgets(
      'chooser D-pad traversal reaches 30 and activation reports 30',
      (WidgetTester tester) async {
        final unlocked = <int>[];
        await pumpOverlay(tester, pin: '1234', unlocked: unlocked);

        await enterDigits(tester, ['1', '2', '3', '4']);
        await tester.pump();
        // One tab moves focus from the 15-button to the 30-button.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(unlocked, [30]);
      },
    );

    testWidgets('Back cannot dismiss the unlockable overlay', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, unlocked: unlocked);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      // maybePop's result is true even when PopScope blocks the pop, so the
      // assertion is on the overlay still being mounted afterwards.
      await navigator.maybePop();
      await tester.pump();
      expect(find.byType(LockOverlay), findsOneWidget);
      expect(unlocked, isEmpty);
    });

    testWidgets(
      'master lock exposes no unlock affordance and back cannot dismiss',
      (WidgetTester tester) async {
        final unlocked = <int>[];
        await pumpOverlay(
          tester,
          message: 'Locked by parent',
          masterLock: true,
          unlocked: unlocked,
        );

        expect(find.text('Locked by parent'), findsOneWidget);
        expect(find.byType(PinPad), findsNothing);
        expect(find.byKey(const Key('unlock-15')), findsNothing);
        expect(find.byKey(const Key('unlock-30')), findsNothing);
        expect(find.byKey(const Key('pin-error')), findsNothing);

        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        await navigator.maybePop();
        await tester.pump();
        expect(find.text('Locked by parent'), findsOneWidget);
        expect(unlocked, isEmpty);
      },
    );

    testWidgets(
      'no PIN set: the chooser shows immediately, no pad',
      (WidgetTester tester) async {
        final unlocked = <int>[];
        await pumpOverlay(tester, pin: '', unlocked: unlocked);

        // The PIN is optional: with none set the parent goes straight to the
        // add-time chooser — no pad, no error.
        expect(find.byType(PinPad), findsNothing);
        expect(find.byKey(const Key('unlock-15')), findsOneWidget);
        expect(find.byKey(const Key('unlock-30')), findsOneWidget);
        expect(find.byKey(const Key('pin-error')), findsNothing);

        await tester.tap(find.byKey(const Key('unlock-15')));
        await tester.pump();
        expect(unlocked, [15]);
      },
    );

    testWidgets(
      'injected verifier decides acceptance: correct entry reveals chooser',
      (WidgetTester tester) async {
        final unlocked = <int>[];
        final checked = <String>[];
        await pumpOverlay(
          tester,
          unlocked: unlocked,
          // A remote verifier (background overlay): '9999' is correct. The
          // loadParentPin value is only consulted for emptiness in this mode.
          pin: 'set',
          verifyPin: (entry) async {
            checked.add(entry);
            if (entry.length < 4) return const PinCheck.incomplete();
            return PinCheck(accepted: entry == '9999', complete: true);
          },
        );

        expect(find.byType(PinPad), findsOneWidget);
        await enterDigits(tester, ['9', '9', '9', '9']);
        await tester.pump();
        expect(find.byKey(const Key('pin-error')), findsNothing);
        expect(find.byKey(const Key('unlock-15')), findsOneWidget);
        await tester.tap(find.byKey(const Key('unlock-15')));
        await tester.pump();
        expect(unlocked, [15]);
        // Every digit reached the verifier, including the incomplete ones.
        expect(checked, ['9', '99', '999', '9999']);
      },
    );

    testWidgets(
      'injected verifier rejects a complete wrong entry: error, pad stays',
      (WidgetTester tester) async {
        final unlocked = <int>[];
        await pumpOverlay(
          tester,
          unlocked: unlocked,
          pin: 'set',
          verifyPin: (entry) async => entry.length < 4
              ? const PinCheck.incomplete()
              : PinCheck(accepted: false, complete: true),
        );

        await enterDigits(tester, ['1', '1', '1', '1']);
        await tester.pump();
        expect(find.byKey(const Key('pin-error')), findsOneWidget);
        expect(find.byType(PinPad), findsOneWidget);
        expect(unlocked, isEmpty);
      },
    );

    testWidgets('locked state shows the switch-over hint above the pad', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, unlocked: unlocked);

      expect(find.byKey(const Key('lock-hint')), findsOneWidget);
      expect(
        find.text('Enter parent PIN to add time or switch profiles'),
        findsOneWidget,
      );
    });

    testWidgets('chooser state shows the no-PIN hint line', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, pin: '', unlocked: unlocked);

      expect(find.byKey(const Key('lock-hint')), findsOneWidget);
      expect(
        find.text('Choose to add time or switch profiles'),
        findsOneWidget,
      );
    });

    testWidgets('master lock copy is unchanged: no switch-over hint', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(
        tester,
        message: 'Locked by parent',
        masterLock: true,
        unlocked: unlocked,
      );

      expect(find.byKey(const Key('lock-hint')), findsNothing);
      expect(find.text('Locked by parent'), findsOneWidget);
      expect(find.text('Unlock from the parent phone app'), findsOneWidget);
    });

    testWidgets('slideshow starts on scene 0 and rotates on the fake clock', (
      WidgetTester tester,
    ) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, unlocked: unlocked);

      expect(find.byKey(const Key('lock-scene-0')), findsOneWidget);

      // Cross-fade every ~8s: advancing fake time rotates to the next scene.
      await tester.pump(const Duration(seconds: 8));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('lock-scene-1')), findsOneWidget);

      // After the fade settles the previous scene is fully replaced.
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('lock-scene-0')), findsNothing);
      expect(find.byKey(const Key('lock-scene-1')), findsOneWidget);
    });

    testWidgets('slideshow sits beneath the scrim, which sits beneath the '
        'content (scene never obscures text)', (WidgetTester tester) async {
      final unlocked = <int>[];
      await pumpOverlay(tester, unlocked: unlocked);

      final stack = tester.widget<Stack>(find.byType(Stack).first);
      expect(stack.children.first, isA<LockSlideshow>());
      final scrim = stack.children[1] as IgnorePointer;
      final box = scrim.child! as ColoredBox;
      expect(box.key, const Key('lock-scrim'));
      // Translucent: the scene stays faintly visible but text stays readable.
      expect(box.color.a, lessThan(1.0));
      expect(box.color.a, greaterThan(0.0));
      // Content (message text) is painted above the scrim.
      final order = tester.allWidgets.toList();
      final contentIdx = order.indexWhere(
        (w) => w is Text && w.data == "Time's up!",
      );
      final scrimIdx = order.indexWhere((w) => w is ColoredBox);
      expect(contentIdx, greaterThan(scrimIdx));
    });
  });

  group('TvHome lock overlay mount', () {
    final today = DateTime(2026, 10, 23);

    late EleenDatabase db;
    late FakeClock clock;
    late TvController controller;

    setUp(() {
      db = EleenDatabase(NativeDatabase.memory());
      clock = FakeClock(today);
      controller = TvController(db: db, clock: clock, speedFactor: 60);
    });

    tearDown(() async {
      controller.dispose();
      await db.close();
    });

    Future<void> seedAndStart({bool masterLock = false}) async {
      await db.saveSettings(
        Settings(parentPin: '1234', masterLockEnabled: masterLock),
      );
      await db.upsertProfile(
        const Profile(
          id: 'p1',
          name: 'Maya',
          avatar: 'fox',
          allowance: AllowanceMinutes.fifteen,
        ),
      );
      await controller.refresh();
      await controller.selectProfile('p1');
    }

    Future<void> pumpHome(
      WidgetTester tester, {
      Future<void> Function()? bringToFront,
      Future<void> Function()? hideBackgroundToast,
      Future<void> Function(Object?)? sendOverlayMessage,
    }) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      await tester.pumpWidget(
        MaterialApp(
          home: TvHome(
            controller: controller,
            bringToFront: bringToFront,
            hideBackgroundToast: hideBackgroundToast,
            sendOverlayMessage: sendOverlayMessage,
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets(
      'pausing while locked brings the app to the front (the in-app lock '
      'keeps covering the TV — a platform overlay cannot take remote input)',
      (WidgetTester tester) async {
        await seedAndStart();
        // Expire the session so the lock is active.
        for (var i = 0; i < 15; i++) {
          clock.advanceMs(1000);
          await controller.tick();
        }
        var frontCalls = 0;
        var hideCalls = 0;
        await pumpHome(
          tester,
          bringToFront: () async {
            frontCalls++;
          },
          hideBackgroundToast: () async {
            hideCalls++;
          },
        );
        expect(find.text("Time's up!"), findsOneWidget);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(frontCalls, 1);

        // Resuming (the bring-forward landed) leaves the in-app lock up.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(hideCalls, 0, reason: 'no platform overlay to hide');
        expect(find.text("Time's up!"), findsOneWidget);
      },
    );

    testWidgets('pausing while unlocked does not bring the app forward', (
      WidgetTester tester,
    ) async {
      await seedAndStart();
      var frontCalls = 0;
      await pumpHome(
        tester,
        bringToFront: () async {
          frontCalls++;
        },
      );
      expect(find.byType(LockOverlay), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(frontCalls, 0);
    });

    testWidgets('a failed bring-to-front retries on the next pause', (
      WidgetTester tester,
    ) async {
      await seedAndStart();
      // Expire the session so the lock is active.
      for (var i = 0; i < 15; i++) {
        clock.advanceMs(1000);
        await controller.tick();
      }
      var frontCalls = 0;
      await pumpHome(
        tester,
        bringToFront: () async {
          frontCalls++;
          // First attempt fails (a transient platform error).
          if (frontCalls == 1) throw StateError('transient');
        },
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(frontCalls, 1);

      // The failure must not latch: the next pause retries.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(frontCalls, 2);
    });

    testWidgets('expiry mounts the overlay; PIN + 15 minutes clears it', (
      WidgetTester tester,
    ) async {
      await seedAndStart();
      await pumpHome(tester);
      expect(find.byType(LockOverlay), findsNothing);
      expect(find.text('15:00'), findsOneWidget);

      // Play the whole 15-minute allowance down to 0.
      for (var i = 0; i < 15; i++) {
        clock.advanceMs(1000);
        await controller.tick();
      }
      await tester.pump();
      expect(find.text("Time's up!"), findsOneWidget);

      // Wrong PIN: error, overlay stays.
      for (final digit in ['1', '2', '3', '9']) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pump();
      }
      expect(find.byKey(const Key('pin-error')), findsOneWidget);
      expect(find.text("Time's up!"), findsOneWidget);

      // Correct PIN, then 15 minutes: add-time runs and the overlay clears.
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pump();
      }
      await tester.pump();
      await tester.tap(find.byKey(const Key('unlock-15')));
      await tester.pump();
      expect(find.text("Time's up!"), findsNothing);
      expect(find.text('15:00'), findsOneWidget);
      final session = controller.state!.activeSession!;
      expect(session.remainingSeconds, 15 * 60);
    });

    testWidgets('master lock overlays the TV home even mid-session', (
      WidgetTester tester,
    ) async {
      await seedAndStart(masterLock: true);
      await pumpHome(tester);

      // Session is live (15:00 remaining) but the parent lock covers it.
      expect(find.text('15:00'), findsOneWidget);
      expect(find.text('Locked by parent'), findsOneWidget);
      expect(find.byType(PinPad), findsNothing);
      expect(find.byKey(const Key('unlock-15')), findsNothing);
    });

    testWidgets('no PIN set: expiry shows the chooser directly and add 15 '
        'clears the overlay', (WidgetTester tester) async {
      // Seed WITHOUT a parent PIN (fresh-install shape).
      await db.saveSettings(const Settings(parentPin: ''));
      await db.upsertProfile(
        const Profile(
          id: 'p1',
          name: 'Maya',
          avatar: 'fox',
          allowance: AllowanceMinutes.fifteen,
        ),
      );
      await controller.refresh();
      await controller.selectProfile('p1');
      for (var i = 0; i < 15; i++) {
        clock.advanceMs(1000);
        await controller.tick();
      }
      await pumpHome(tester);

      // No pad: the chooser is up straight away.
      expect(find.text("Time's up!"), findsOneWidget);
      expect(find.byType(PinPad), findsNothing);
      expect(find.byKey(const Key('unlock-15')), findsOneWidget);

      await tester.tap(find.byKey(const Key('unlock-15')));
      await tester.pump();
      expect(find.text("Time's up!"), findsNothing);
      expect(find.text('15:00'), findsOneWidget);
    });

    testWidgets('pausing while master-locked brings the app to the front', (
      WidgetTester tester,
    ) async {
      await seedAndStart(masterLock: true);
      var frontCalls = 0;
      await pumpHome(
        tester,
        bringToFront: () async {
          frontCalls++;
        },
      );
      expect(find.text('Locked by parent'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(frontCalls, 1);
    });

    testWidgets('unlocked while backgrounded: the bring-forward flag resets '
        'and no platform overlay is involved', (
      WidgetTester tester,
    ) async {
      await seedAndStart();
      for (var i = 0; i < 15; i++) {
        clock.advanceMs(1000);
        await controller.tick();
      }
      var frontCalls = 0;
      var hideCalls = 0;
      await pumpHome(
        tester,
        bringToFront: () async {
          frontCalls++;
        },
        hideBackgroundToast: () async {
          hideCalls++;
        },
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(frontCalls, 1);

      // The lock clears from outside the isolate-under-test (the parent
      // phone adds time through the server): the server mutates the db, and
      // the TV learns of it on its next tick-driven refresh while still
      // backgrounded — nothing platform-side to close.
      final remaining = await controller.coordinator.addTime('p1', 15 * 60);
      expect(remaining, isNotNull);
      await controller.refresh();
      await tester.pumpAndSettle();
      expect(hideCalls, 0);
      // The in-app lock dismissal itself is covered by the expiry/PIN test
      // above; this test only cares that nothing platform-side happened.
    });

  });
}
