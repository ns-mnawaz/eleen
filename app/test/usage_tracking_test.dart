// Daily usage records on the TV controller (v1.1 D): per-tick usedSeconds
// accrual, the shutdown-recovery marker, limitHit / sessionStart /
// sessionEnd events, parent usage (no limits, but usage recorded), and the
// date rollover booking.

import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mutable [Clock]: monotonic time and the calendar date advance only when
/// the test advances them, so ticks are fully deterministic.
class MutableClock implements Clock {
  MutableClock(this.date);

  DateTime date;
  int _ms = 0;

  void advanceMs(int ms) => _ms += ms;

  /// Moves to the NEXT calendar day (midnight rollover); the monotonic
  /// clock keeps running, like a device left on overnight.
  void nextDay() {
    date = date.add(const Duration(days: 1));
  }

  @override
  int nowMs() => _ms;

  @override
  DateTime today() => date;
}

void main() {
  final today = DateTime(2026, 10, 24);

  late EleenDatabase db;
  late MutableClock clock;
  late TvController controller;

  setUp(() {
    db = EleenDatabase(NativeDatabase.memory());
    clock = MutableClock(today);
    // E2E speed: 1 wall second consumes 60 session seconds.
    controller = TvController(db: db, clock: clock, speedFactor: 60);
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> seedChild() async {
    await db.upsertProfile(const Profile(
      id: 'kid',
      name: 'Maya',
      avatar: 'fox',
      allowance: AllowanceMinutes.fifteen,
    ));
    await controller.refresh();
  }

  Future<void> seedParent() async {
    await db.upsertProfile(const Profile(
      id: 'parent',
      name: 'Ava',
      avatar: 'bear',
      allowance: AllowanceMinutes.thirty,
      isParent: true,
    ));
    await controller.refresh();
  }

  test('each tick accrues usedSeconds (speedFactor session units)', () async {
    await seedChild();
    await controller.selectProfile('kid');

    clock.advanceMs(1000);
    await controller.tick();

    expect(await db.usedSecondsFor('kid', today), 60);
  });

  test('accrual is capped at the remaining time (no usage past expiry)',
      () async {
    await seedChild();
    await controller.selectProfile('kid');

    // 14 one-second ticks leave 60 session seconds (900 - 14*60).
    for (var i = 0; i < 14; i++) {
      clock.advanceMs(1000);
      await controller.tick();
    }
    expect((await db.sessionFor(today))!.remainingSeconds, 60);
    // A 1.5-second tick would consume 90 session seconds, but only 60 are
    // left: the accrual must cap at what was actually played.
    clock.advanceMs(1500);
    await controller.tick();

    // 15 minutes = 900 session seconds, all consumed, none invented.
    expect(await db.usedSecondsFor('kid', today), 900);
    expect((await db.sessionFor(today))!.remainingSeconds, 0);
  });

  test('the tick marker (lastTickUptimeMs) is persisted every tick',
      () async {
    await seedChild();
    await controller.selectProfile('kid');

    clock.advanceMs(1000);
    await controller.tick();
    clock.advanceMs(1500);
    await controller.tick();

    expect(
        await db.getMetaInt(EleenDatabase.lastTickUptimeMsKey), 2500);
    // The marker is written even with no active session.
    await controller.endActiveSession();
    clock.advanceMs(1000);
    await controller.tick();
    expect(
        await db.getMetaInt(EleenDatabase.lastTickUptimeMsKey), 3500);
  });

  test('limitHit is recorded exactly once when remaining reaches 0',
      () async {
    await seedChild();
    await controller.selectProfile('kid');

    for (var i = 0; i < 15; i++) {
      clock.advanceMs(1000);
      await controller.tick();
    }
    // Keep ticking past expiry: no duplicates.
    clock.advanceMs(1000);
    await controller.tick();

    final types =
        (await db.eventsFor('kid')).map((e) => e.type).toList();
    expect(types.where((t) => t == UsageEventType.limitHit), hasLength(1));
  });

  test('selectProfile records sessionStart; switching records sessionEnd '
      'for the deactivated profile', () async {
    await seedChild();
    await db.upsertProfile(const Profile(
      id: 'kid-2',
      name: 'Leo',
      avatar: 'bear',
      allowance: AllowanceMinutes.thirty,
    ));
    await controller.refresh();

    await controller.selectProfile('kid');
    await controller.selectProfile('kid-2');

    final kidEvents = (await db.eventsFor('kid')).map((e) => e.type);
    expect(kidEvents, [UsageEventType.sessionStart, UsageEventType.sessionEnd]);
    expect((await db.eventsFor('kid-2')).single.type,
        UsageEventType.sessionStart);
  });

  test('endActiveSession records sessionEnd', () async {
    await seedChild();
    await controller.selectProfile('kid');

    await controller.endActiveSession();

    expect((await db.eventsFor('kid')).map((e) => e.type),
        [UsageEventType.sessionStart, UsageEventType.sessionEnd]);
  });

  test('a parent session accrues usage without burning remaining time',
      () async {
    await seedParent();
    await controller.selectProfile('parent');

    for (var i = 0; i < 5; i++) {
      clock.advanceMs(1000);
      await controller.tick();
    }

    // Usage IS recorded (parents are profiles too)...
    expect(await db.usedSecondsFor('parent', today), 5 * 60);
    // ...but the parent session never expires (no limitHit, no ticking of
    // remaining).
    expect(
        (await db.eventsFor('parent'))
            .where((e) => e.type == UsageEventType.limitHit),
        isEmpty);
    final session = await db.sessionForProfile('parent', today);
    expect(session!.remainingSeconds, 30 * 60); // untouched
  });

  test('rollover books usage per day: the previous day keeps its total',
      () async {
    await seedChild();
    await controller.selectProfile('kid');

    // 3 ticks on Oct 24.
    for (var i = 0; i < 3; i++) {
      clock.advanceMs(1000);
      await controller.tick();
    }

    // Midnight passes while the session runs (Oct 24 -> Oct 25). The
    // rollover tick itself books nothing (the engine discards the elapsed
    // wall time while refilling); the next two ticks book to the new day.
    clock.nextDay();
    for (var i = 0; i < 3; i++) {
      clock.advanceMs(1000);
      await controller.tick();
    }

    final nextDay = today.add(const Duration(days: 1));
    // Usage before the rollover belongs to Oct 24, after to Oct 25; the
    // previous day's row is preserved (recorded before the reset).
    expect(await db.usedSecondsFor('kid', today), 3 * 60);
    expect(await db.usedSecondsFor('kid', nextDay), 2 * 60);
    // The history carries both days, newest first.
    final history = await db.usageHistory('kid');
    expect(history.map((d) => d.date), [nextDay, today]);
  });

  test('recoverShutdown delegates to the coordinator (pair on relaunch)',
      () async {
    await seedChild();
    await controller.selectProfile('kid');
    clock.advanceMs(1000);
    await controller.tick();

    // A "relaunch": a new controller over the same database (the tick
    // marker exists from the previous run).
    final relaunched = TvController(db: db, clock: clock, speedFactor: 60);
    await relaunched.recoverShutdown();

    final global =
        (await db.eventsFor(EleenDatabase.appGlobalProfileId))
            .map((e) => e.type);
    expect(global, [UsageEventType.shutdown, UsageEventType.powerOn]);
    relaunched.dispose();
  });
}
