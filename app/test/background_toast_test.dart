// Background reminder toasts (v1.2): while the TV app is backgrounded and
// nothing is locked, a reminder threshold ("10 minutes left") surfaces over
// whatever app is running (YouTube, ...) via the platform overlay in its
// transparent, click-through toast mode. While resumed, the countdown screen
// shows reminders in-app instead; while locked, the lock owns the screen.


import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/tv_home.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mutable [Clock] — ticks are fully deterministic (see countdown tests).
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

  setUp(() async {
    db = EleenDatabase(NativeDatabase.memory());
    clock = FakeClock(today);
    controller = TvController(db: db, clock: clock, speedFactor: 60);
    await db.upsertProfile(const Profile(
      id: 'p1',
      name: 'Maya',
      avatar: 'fox',
      allowance: AllowanceMinutes.fifteen,
    ));
    await controller.refresh();
    await controller.selectProfile('p1');
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> tickSeconds(int n) async {
    for (var i = 0; i < n; i++) {
      clock.advanceMs(1000);
      await controller.tick();
    }
  }

  testWidgets('a reminder while backgrounded and unlocked shows the toast '
      'platform overlay and pushes the message to the engine',
      (WidgetTester tester) async {
    final shownToasts = <bool>[];
    final hidden = <int>[];
    final pushed = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        showBackgroundToast: () async {
          shownToasts.add(true);
          return true;
        },
        hideBackgroundToast: () async => hidden.add(1),
        bringToFront: () async => true,
        sendOverlayMessage: (m) async => pushed.add(m),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // The TV app goes to the background (someone opened YouTube).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // Nothing locked (session at 15:00) and the 10-minute threshold is
    // still ahead: tick down to it (900 -> 540 crosses 600).
    await tickSeconds(6);

    expect(shownToasts, [true], reason: 'the toast-mode overlay was shown');
    expect(
      pushed,
      containsAll([
        predicate<Map>((m) =>
            m['type'] == 'toast' && m['message'] == '10 minutes left'),
      ]),
      reason: 'the reminder was pushed to the overlay engine',
    );
    // No lock overlay was requested.
    expect(hidden, isEmpty);

    // ~5.5s later the toast-mode overlay closes (the pill showed ~5s).
    await tester.pump(const Duration(milliseconds: 5600));
    expect(hidden, [1]);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a reminder while the app is resumed never shows the platform '
      'overlay (the in-app toast covers it)', (WidgetTester tester) async {
    var shownToasts = 0;
    final pushed = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        showBackgroundToast: () async {
          shownToasts++;
          return true;
        },
        bringToFront: () async => true,
        sendOverlayMessage: (m) async => pushed.add(m),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Foregrounded: the threshold fires in-app.
    await tickSeconds(6);
    expect(shownToasts, 0);
    expect(pushed.whereType<Map>().where((m) => m['type'] == 'toast'),
        isEmpty);
  });

  testWidgets('a lock engaging mid-toast swaps the toast overlay for the '
      'lock overlay', (WidgetTester tester) async {
    final shownToasts = <int>[];
    final broughtToFront = <int>[];
    final hidden = <int>[];
    final pushed = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        showBackgroundToast: () async {
          shownToasts.add(1);
          return true;
        },
        bringToFront: () async => broughtToFront.add(1),
        hideBackgroundToast: () async => hidden.add(1),
        sendOverlayMessage: (m) async => pushed.add(m),
      ),
    ));
    await tester.pump();
    await tester.pump();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // Toast mode first (the 10-minute reminder over YouTube).
    await tickSeconds(6);
    expect(shownToasts, [1]);
    await tester.pump();

    // The session expires while still backgrounded: the controller listener
    // swaps the click-through toast overlay for the full lock.
    await tickSeconds(9);
    // Flush the async swap chain (hide -> show -> db read -> state push).
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(broughtToFront, [1],
        reason: 'the lock brings the app to the front (in-app lock takes '
            'over — the platform overlay cannot take remote key input)');
    expect(hidden, isNotEmpty,
        reason: 'the toast overlay closed on the swap');
    // No lockState push anymore: the engine is display-only.
    expect(pushed.whereType<Map>().where((m) => m['type'] == 'lockState'),
        isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('time\'s up while backgrounded (no toast overlay up) brings the '
      'app to the front with the lock', (WidgetTester tester) async {
    final broughtToFront = <int>[];
    final shownToasts = <int>[];
    final pushed = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        bringToFront: () async => broughtToFront.add(1),
        showBackgroundToast: () async {
          shownToasts.add(1);
          return true;
        },
        hideBackgroundToast: () async {},
        sendOverlayMessage: (m) async => pushed.add(m),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // The TV app goes to the background right away (no toast ever showed:
    // the child left at 15:00). Session plays out unattended to expiry.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tickSeconds(15);
    // Flush the async show chain (db read -> lock-state push).
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(broughtToFront, [1],
        reason: 'the lock brings the app to the front at expiry, covering '
            'the running app with the in-app lock');
    // No lockState push anymore: the engine is display-only.
    expect(pushed.whereType<Map>().where((m) => m['type'] == 'lockState'),
        isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('time\'s up while the Eleen app is visible never shows the '
      'platform lock (the in-app lock covers it)', (WidgetTester tester) async {
    final broughtToFront = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        bringToFront: () async => broughtToFront.add(1),
        showBackgroundToast: () async => true,
        hideBackgroundToast: () async {},
        sendOverlayMessage: (_) async {},
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Foregrounded all the way to expiry.
    await tickSeconds(15);
    await tester.pump();
    expect(broughtToFront, isEmpty,
        reason: 'the in-app lock overlay covers a visible app');
  });

  testWidgets('the final minute renders a live countdown over the running '
      'app, then the lock takes over at expiry', (WidgetTester tester) async {
    final shownToasts = <int>[];
    final broughtToFront = <int>[];
    final hidden = <int>[];
    final pushed = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        showBackgroundToast: () async {
          shownToasts.add(1);
          return true;
        },
        bringToFront: () async => broughtToFront.add(1),
        hideBackgroundToast: () async => hidden.add(1),
        sendOverlayMessage: (m) async => pushed.add(m),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Backgrounded at 15:00 (900s). Each wall second is 60 session seconds
    // at speedFactor 60: 14 ticks land at 60s — the final minute begins.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tickSeconds(14);

    expect(shownToasts, isNotEmpty,
        reason: 'the click-through overlay is up for the final minute');
    expect(
      pushed.whereType<Map>().any((m) =>
          m['type'] == 'lastMinute' && m['seconds'] == 60),
      isTrue,
      reason: 'the remaining seconds were pushed to the overlay engine',
    );

    // It ticks per second while the badge is up (no auto-close: the
    // transient toast close timer must not tear down the last-minute
    // overlay). 60 -> 0 in one more wall second.
    await tickSeconds(1);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(broughtToFront, [1],
        reason: 'expiry brings the app to the front with the lock');
    // No lockState push anymore: the engine is display-only.
    expect(pushed.whereType<Map>().where((m) => m['type'] == 'lockState'),
        isEmpty);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the last-minute overlay never shows while the app is '
      'visible (the in-app badge covers it)', (WidgetTester tester) async {
    final shownToasts = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        showBackgroundToast: () async {
          shownToasts.add(1);
          return true;
        },
        bringToFront: () async => true,
        hideBackgroundToast: () async {},
        sendOverlayMessage: (_) async {},
      ),
    ));
    await tester.pump();
    await tester.pump();

    // Foregrounded into the final minute and to expiry.
    await tickSeconds(15);
    await tester.pump();
    expect(shownToasts, isEmpty,
        reason: 'the in-app last-minute badge and lock cover a visible app');
  });

  testWidgets('full background sequence: toasts surface over the running '
      'app, then the lock takes over at expiry and STAYS up',
      (WidgetTester tester) async {
    final shownToasts = <int>[];
    final broughtToFront = <int>[];
    final hidden = <int>[];
    final pushed = <Object?>[];
    await tester.pumpWidget(MaterialApp(
      home: TvHome(
        controller: controller,
        showBackgroundToast: () async {
          shownToasts.add(1);
          return true;
        },
        bringToFront: () async => broughtToFront.add(1),
        hideBackgroundToast: () async => hidden.add(1),
        sendOverlayMessage: (m) async => pushed.add(m),
      ),
    ));
    await tester.pump();
    await tester.pump();

    // The app goes to the background at 15:00; another app runs.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // 900 -> 540: the 10-minute reminder surfaces over the running app
    // (the threshold fires strictly below 600, so 6 ticks).
    await tickSeconds(6);
    expect(shownToasts, hasLength(1));
    expect(
      pushed.whereType<Map>().any((m) =>
          m['type'] == 'toast' && m['message'] == '10 minutes left'),
      isTrue,
    );

    // The toast overlay auto-closes after the pill's lifetime.
    await tester.pump(const Duration(milliseconds: 5600));
    expect(hidden, hasLength(1));

    // 540 -> 240: the 5-minute reminder re-shows the toast overlay
    // (strictly below 300, so 5 ticks).
    await tickSeconds(5);
    expect(shownToasts, hasLength(2));
    expect(
      pushed.whereType<Map>().any((m) =>
          m['type'] == 'toast' && m['message'] == '5 minutes left'),
      isTrue,
    );

    // 240 -> 0: time is up while still backgrounded. The lock overlay
    // takes over from the toast overlay and is shown exactly once.
    await tickSeconds(4);
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(broughtToFront, [1],
        reason: 'the app came to the front at expiry (lock shown in-app)');
    // No lockState push anymore: the engine is display-only.
    expect(pushed.whereType<Map>().where((m) => m['type'] == 'lockState'),
        isEmpty);

    // The guard persists: well past the toast close timer's window, the
    // lock stays up (nothing else fired). The two hides are the 10-minute
    // toast's auto-close and the toast->lock swap.
    await tester.pump(const Duration(seconds: 8));
    expect(broughtToFront, [1]);
    expect(hidden, hasLength(2),
        reason: 'the 10-min toast auto-close + the mode swap; nothing else '
            'hid anything');

    await tester.pumpWidget(const SizedBox());
  });
}
