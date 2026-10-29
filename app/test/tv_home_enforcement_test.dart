// TV home enforcement: with no countdown screen, the home owns the tick
// loop and shows a compact status row (profile name + live remaining m:ss +
// wall-clock pill) while a child session is enforced. Reminder toasts and
// the last-minute badge render in-app while the home is visible. This
// carries the coverage that used to live on the (now deleted) countdown
// screen, plus the bringToFront seam for pausing other apps when the lock engages
// in the background.

import 'dart:async';

import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/tv_home.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
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

void main() {
  final today = DateTime(2026, 10, 23);

  late EleenDatabase db;
  late FakeClock clock;
  late TvController controller;
  final toastEvents = <String>[];

  /// Seam state for the overlay-permission tests below.
  bool overlayGranted = true;
  final permissionRequests = <int>[];
  StreamSubscription<String>? toastSub;

  setUp(() {
    overlayGranted = true;
    permissionRequests.clear();
    db = EleenDatabase(NativeDatabase.memory());
    clock = FakeClock(today);
    // E2E speed: 1 wall second consumes 60 session seconds.
    controller = TvController(db: db, clock: clock, speedFactor: 60);
    toastEvents.clear();
    toastSub = controller.toasts.listen(toastEvents.add);
  });

  tearDown(() async {
    await toastSub?.cancel();
    controller.dispose();
    await db.close();
  });

  Future<void> seedProfile() async {
    await db.upsertProfile(const Profile(
      id: 'p1',
      name: 'Maya',
      avatar: 'fox',
      allowance: AllowanceMinutes.fifteen,
    ));
    await controller.refresh();
  }

  /// Starts a 15-minute session: 900 session seconds remaining.
  Future<void> startSession() async {
    await seedProfile();
    await controller.selectProfile('p1');
  }

  /// Advances the fake clock [n] wall seconds and ticks the controller once
  /// per second (exactly what the real Timer.periodic loop does).
  Future<void> tickSeconds(int n) async {
    for (var i = 0; i < n; i++) {
      clock.advanceMs(1000);
      await controller.tick();
    }
  }

  Widget pumpHome({
    List<int>? bringToFrontCalls,
    bool showToast = true,
    int failBringToFrontTimes = 0,
  }) {
    return MaterialApp(
      home: TvHome(
        controller: controller,
        // The periodic loop is driven by hand in the tests below.
        tickInterval: const Duration(hours: 1),
        hideBackgroundToast: () async {},
        showBackgroundToast: () async => showToast,
        bringToFront: bringToFrontCalls == null
            ? null
            : () async {
                bringToFrontCalls.add(1);
                if (bringToFrontCalls.length <= failBringToFrontTimes) {
                  throw StateError('background activity start blocked');
                }
              },
        // Widget tests have no platform channel: never hit the real one.
        sessionServiceStart: () async {},
        sessionServiceStop: () async {},
        sendOverlayMessage: (_) async {},
        overlayPermissionGranted: () async => overlayGranted,
        requestOverlayPermission: () async {
          permissionRequests.add(1);
          return true;
        },
      ),
    );
  }

  /// The live remaining text on the status row, or null when absent.
  String? remainingText(WidgetTester tester) {
    final finder = find.byKey(const Key('enforced-remaining'));
    if (finder.evaluate().isEmpty) return null;
    return tester.widget<Text>(finder).data;
  }

  testWidgets('home status row shows the remaining time as m:ss and the '
      'tick loop advances it', (WidgetTester tester) async {
    await startSession();
    await tester.pumpWidget(pumpHome());
    await tester.pump();

    expect(find.byKey(const Key('countdown-compact')), findsOneWidget,
        reason: 'the wall-clock pill is on the status row');
    expect(remainingText(tester), '15:00');

    // One wall second at speedFactor 60 consumes 60 session seconds.
    await tickSeconds(1);
    await tester.pump();
    expect(remainingText(tester), '14:00');
  });

  testWidgets('the status row is absent while no child session is enforced',
      (WidgetTester tester) async {
    await seedProfile();
    await tester.pumpWidget(pumpHome());
    await tester.pump();

    expect(find.byKey(const Key('enforced-remaining')), findsNothing);
    expect(find.byKey(const Key('countdown-compact')), findsNothing);
    // The picker is always the main screen.
    expect(find.byKey(const Key('profile-card-p1')), findsOneWidget);
  });

  testWidgets('reminder toasts show in-app once at the 10- and 5-minute '
      'marks', (WidgetTester tester) async {
    await startSession();
    await tester.pumpWidget(pumpHome());
    await tester.pump();

    // 900 -> 600: crosses the 10-minute threshold on the 5th tick.
    await tickSeconds(5);
    await tester.pump();
    expect(find.byKey(const Key('reminder-toast')), findsOneWidget);
    expect(find.text('10 minutes left'), findsOneWidget);

    // Toasts are transient: gone after ~5 seconds.
    await tester.pump(const Duration(seconds: 5));
    expect(find.byKey(const Key('reminder-toast')), findsNothing);

    // 600 -> 300: crosses the 5-minute threshold on the 5th tick.
    await tickSeconds(5);
    await tester.pump();
    expect(find.text('5 minutes left'), findsOneWidget);

    // Keep playing down: neither toast fires again.
    await tester.pump(const Duration(seconds: 5));
    await tickSeconds(3);
    await tester.pump();
    expect(find.byKey(const Key('reminder-toast')), findsNothing);
    expect(toastEvents, ['10 minutes left', '5 minutes left']);
  });

  testWidgets('the last-minute badge appears only in the final session-minute',
      (WidgetTester tester) async {
    await startSession();
    // Jump below the last minute without ticking: no threshold crossings.
    await controller.coordinator.overrideRemaining('p1', 120);
    await controller.refresh();
    await tester.pumpWidget(pumpHome());
    await tester.pump();

    final lastMinute = find.byKey(const Key('last-minute-countdown'));
    expect(lastMinute, findsNothing);

    // Inside the window (60 remaining session seconds): visible, m:ss.
    await controller.coordinator.overrideRemaining('p1', 60);
    await controller.refresh();
    await tester.pump();
    expect(lastMinute, findsOneWidget);

    // Expired (0): the badge is gone; the lock overlay takes over.
    clock.advanceMs(1000);
    await controller.tick();
    await tester.pump();
    expect(lastMinute, findsNothing);
    expect(find.byKey(const Key('lock-overlay')), findsOneWidget);
  });

  testWidgets('the lock engaging while the app is visible never sends the '
      'device home (the in-app lock covers it)', (WidgetTester tester) async {
    final bringToFrontCalls = <int>[];
    await startSession();
    await tester.pumpWidget(pumpHome(bringToFrontCalls: bringToFrontCalls));
    await tester.pump();

    // Foregrounded all the way to expiry.
    await tickSeconds(15);
    await tester.pump();
    expect(find.byKey(const Key('lock-overlay')), findsOneWidget);
    expect(bringToFrontCalls, isEmpty,
        reason: 'going home while visible would background Eleen itself');
  });

  testWidgets('the lock engaging while the app is backgrounded sends the '
      'device home so a running app pauses', (WidgetTester tester) async {
    final bringToFrontCalls = <int>[];
    await startSession();
    await tester.pumpWidget(pumpHome(bringToFrontCalls: bringToFrontCalls));
    await tester.pump();

    // The TV app goes to the background (someone opened YouTube), then the
    // session plays out to expiry.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tickSeconds(15);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(bringToFrontCalls, [1], reason: 'the lock pauses the running app');
  });

  testWidgets('leaving a locked Eleen to the background sends the device '
      'home so an app launched over the lock pauses', (tester) async {
    final bringToFrontCalls = <int>[];
    await startSession();
    await tester.pumpWidget(pumpHome(bringToFrontCalls: bringToFrontCalls));
    await tester.pump();

    // Expire while visible: the in-app lock engages, no bringToFront yet.
    await tickSeconds(15);
    await tester.pump();
    expect(find.byKey(const Key('lock-overlay')), findsOneWidget);
    expect(bringToFrontCalls, isEmpty);

    // The child leaves the locked Eleen (or launches another app over it):
    // the app is now backgrounded and must send the device home so whatever
    // is in front pauses under the lock.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(bringToFrontCalls, [1],
        reason: 'a real background transition pauses the app in front');

    // The hidden -> paused pair must not send home twice.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(bringToFrontCalls, [1]);

    // Resuming re-arms it for the next background stretch.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(bringToFrontCalls, [1, 1]);
  });

  testWidgets('a bring-to-front that fails is retried on the next tick — it '
      'must not latch the lock off', (WidgetTester tester) async {
    final bringToFrontCalls = <int>[];
    await startSession();
    await tester.pumpWidget(pumpHome(
      bringToFrontCalls: bringToFrontCalls,
      failBringToFrontTimes: 2,
    ));
    await tester.pump();

    // The child is in YouTube and the session plays out to expiry: 15 ticks
    // reach 0 (the tick that engages the lock), then five more ticks with
    // the session sitting at 0 — each one a chance to retry.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tickSeconds(20);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    // Attempts 1 and 2 threw (a blocked background activity start): the home
    // must retry rather than latch — a latched flag would leave the lock
    // down and the child watching YouTube for the whole background stretch.
    // Attempt 3 succeeds and latches again, so the retries stop there: no
    // per-tick hammering once Eleen is actually in front.
    expect(bringToFrontCalls.length, 3,
        reason: 'a failed bring-to-front must be retried on the next tick, '
            'and a successful one must latch');

    await tester.pumpWidget(const SizedBox());
  });

  /// Lets async broadcast-stream deliveries catch up (plain tests only;
  /// widget tests flush via tester.pump).
  Future<void> flushToasts() => Future<void>.delayed(Duration.zero);

  test('toasts re-arm after addTime and refire when played down again',
      () async {
    await startSession();

    // 900 -> 600: the 10-minute toast fires once.
    await tickSeconds(5);
    await flushToasts();
    expect(toastEvents, ['10 minutes left']);

    // Adding 600 session seconds re-arms the 600 threshold.
    await controller.coordinator.addTime('p1', 600);
    await controller.refresh();

    // 1200 -> 600: it fires a second time.
    await tickSeconds(10);
    await flushToasts();
    expect(toastEvents, ['10 minutes left', '10 minutes left']);
  });

  test('selecting a profile deactivates the other active session', () async {
    await seedProfile();
    await db.upsertProfile(const Profile(
      id: 'p2',
      name: 'Leo',
      avatar: 'lion',
      allowance: AllowanceMinutes.fifteen,
    ));
    await controller.refresh();

    await controller.selectProfile('p1');
    await controller.selectProfile('p2');

    // Picking Leo ends Maya's session: exactly one enforced profile.
    final p1 = await db.sessionForProfile('p1', today);
    expect(p1, isNotNull);
    expect(p1!.active, isFalse);
    // Her remaining time is preserved so she can resume later.
    expect(p1.remainingSeconds, 15 * 60);
    expect(controller.state!.activeSession!.profileId, 'p2');
  });

  test('ticking only advances the active session', () async {
    await seedProfile();
    await controller.selectProfile('p1');

    await tickSeconds(2);

    final session = controller.state!.activeSession!;
    expect(session.profileId, 'p1');
    expect(session.remainingSeconds, 15 * 60 - 2 * 60);
  });

  testWidgets('enforcement without the overlay permission pins a grant '
      'banner on the home; the button opens the system grant screen',
      (tester) async {
    overlayGranted = false;
    await tester.pumpWidget(pumpHome());
    await tester.pump();

    // No enforcement yet: no banner.
    expect(find.byKey(const Key('overlay-permission-banner')), findsNothing);

    // Enforce: the probe runs, the permission is denied -> banner.
    await startSession();
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.byKey(const Key('overlay-permission-banner')),
        findsOneWidget);
    expect(find.textContaining('Display over other apps'), findsOneWidget);

    // The grant button routes to the system screen.
    await tester.tap(find.byKey(const Key('overlay-permission-grant')));
    await tester.pump();
    expect(permissionRequests, [1]);
  });

  testWidgets('the banner clears on resume once the permission is granted',
      (tester) async {
    overlayGranted = false;
    await tester.pumpWidget(pumpHome());
    await tester.pump();
    await startSession();
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.byKey(const Key('overlay-permission-banner')),
        findsOneWidget);

    // The parent granted it in system settings; the app resumes and
    // re-probes.
    overlayGranted = true;
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('overlay-permission-banner')), findsNothing);
  });

  testWidgets('granted permission: no banner ever', (tester) async {
    overlayGranted = true;
    await tester.pumpWidget(pumpHome());
    await tester.pump();
    await startSession();
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.byKey(const Key('overlay-permission-banner')), findsNothing);
  });

  testWidgets('the settings-row chip always shows the permission status; '
      'tapping opens the system settings and re-probes', (tester) async {
    // Granted on an idle picker: green chip, no banner (no enforcement).
    overlayGranted = true;
    await tester.pumpWidget(pumpHome());
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('overlay-permission-status')), findsOneWidget);
    expect(find.byKey(const Key('overlay-permission-status-granted')),
        findsOneWidget);
    expect(find.byKey(const Key('overlay-permission-banner')), findsNothing);
    // The probe result is published to the coordinator for paired phones.
    expect(controller.coordinator.overlayPermissionGranted, isTrue);

    // Denied: red chip on the idle picker (the banner still waits for
    // enforcement), and the coordinator mirrors the denial.
    overlayGranted = false;
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('overlay-permission-status-denied')),
        findsOneWidget);
    expect(controller.coordinator.overlayPermissionGranted, isFalse);

    // The chip is the settings link: tapping routes to the system screen
    // and re-probes, so a grant made there flips the chip immediately.
    overlayGranted = true;
    await tester.tap(find.byKey(const Key('overlay-permission-status')));
    await tester.pump();
    await tester.pump();
    expect(permissionRequests, [1]);
    expect(find.byKey(const Key('overlay-permission-status-granted')),
        findsOneWidget);
    expect(controller.coordinator.overlayPermissionGranted, isTrue);
  });
}
