// The session foreground service (background countdown): while a CHILD
// session is active the service runs so the OS keeps the process (and the
// per-second tick) alive behind other apps; when the session ends, expires
// or a parent takes over, it stops. The engine bills real wall-clock time,
// so even a suspended process is charged in full on its next tick — this
// just makes that suspension unlikely.

import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/tv_home.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClock implements Clock {
  _FakeClock(this.date);

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
  late _FakeClock clock;
  late TvController controller;

  setUp(() async {
    db = EleenDatabase(NativeDatabase.memory());
    clock = _FakeClock(today);
    controller = TvController(db: db, clock: clock, speedFactor: 60);
    await db.upsertProfile(const Profile(
      id: 'kid',
      name: 'Maya',
      avatar: 'fox',
      allowance: AllowanceMinutes.fifteen,
    ));
    await db.upsertProfile(const Profile(
      id: 'parent',
      name: 'Ava',
      avatar: 'A',
      allowance: AllowanceMinutes.thirty,
      isParent: true,
    ));
    await controller.refresh();
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

  Widget pumpHome(List<String> events) => MaterialApp(
        home: TvHome(
          controller: controller,
          sessionServiceStart: () async => events.add('start'),
          sessionServiceStop: () async => events.add('stop'),
          bringToFront: () async {},
          showBackgroundToast: () async => true,
          hideBackgroundToast: () async {},
          sendOverlayMessage: (_) async {},
        ),
      );

  testWidgets('a child session running starts the service; ending the '
      'session stops it', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(pumpHome(events));
    await tester.pump();
    expect(events, isEmpty, reason: 'no session yet: no service');

    await controller.selectProfile('kid');
    await tester.pump();
    expect(events, ['start'], reason: 'child session active: service up');

    // While the session keeps ticking nothing extra fires.
    await tickSeconds(3);
    await tester.pump();
    expect(events, ['start']);

    // The session expires into the lock — but stays ACTIVE (it resumes when
    // the parent adds time, and the lock's PIN round-trips need this
    // process alive), so the service keeps running.
    await tickSeconds(15);
    await tester.pump();
    await tester.pump();
    expect(events, ['start'],
        reason: 'the locked session is still active: service stays up');

    // Actually ending the session (Switch profile on the lock) stops it.
    await controller.endActiveSession();
    await tester.pump();
    expect(events, ['start', 'stop'],
        reason: 'the session ended: service down');
  });

  testWidgets('a parent session never runs the service',
      (tester) async {
    final events = <String>[];
    await tester.pumpWidget(pumpHome(events));
    await tester.pump();

    await controller.selectProfile('parent');
    await tester.pump();
    await tickSeconds(5);
    await tester.pump();
    expect(events, isEmpty,
        reason: 'parent sessions never burn time — no countdown to keep '
            'alive');
  });

  testWidgets('suspended-process billing: a big clock gap between ticks is '
      'charged in full on the next tick', (tester) async {
    final events = <String>[];
    await tester.pumpWidget(pumpHome(events));
    await tester.pump();
    await controller.selectProfile('kid');
    await tester.pump();

    // The process is frozen for 10 wall minutes (600s wall -> the clock
    // jumps); the next tick bills the whole gap (speedFactor 60 in these
    // tests: 600 wall seconds = 60000 session seconds, far past expiry).
    clock.advanceMs(10 * 60 * 1000);
    await controller.tick();
    await tester.pump();
    await tester.pump();

    // The session expired from the suspended gap alone; the lock holds and
    // the service stays up (the session is still active under the lock).
    expect(events, ['start']);
    expect(TvController.isLocked(controller.state), isTrue);
    expect(controller.state?.activeSession?.remainingSeconds ?? 1, 0);
  });
}
