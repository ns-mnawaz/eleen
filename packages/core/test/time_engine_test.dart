import 'package:eleen_core/eleen_core.dart';
import 'package:test/test.dart';

/// Deterministic [Clock] for tests.
class FakeClock implements Clock {
  FakeClock({required DateTime today}) : _today = today;

  int _ms = 0;
  DateTime _today;

  void elapseMs(int ms) => _ms += ms;

  @override
  int nowMs() => _ms;

  @override
  DateTime today() => _today;
}

SessionState _session({
  String profileId = 'p1',
  DateTime? date,
  int remainingSeconds = 900,
  bool active = true,
}) {
  return SessionState(
    profileId: profileId,
    date: date ?? DateTime(2026, 10, 23),
    remainingSeconds: remainingSeconds,
    active: active,
  );
}

void main() {
  group('advance', () {
    test('subtracts elapsed time scaled by speedFactor', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));
      final s = _session(remainingSeconds: 900);

      final s2 = engine.advance(s, 60000, AllowanceMinutes.fifteen);

      expect(s2.remainingSeconds, 840);
      expect(s2.active, isTrue);
      expect(s2.profileId, 'p1');
    });

    test('floors remaining at 0 and never goes negative', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));
      final s = _session(remainingSeconds: 30);

      final s2 = engine.advance(s, 60000, AllowanceMinutes.fifteen);

      expect(s2.remainingSeconds, 0);
    });

    test('date rollover resets remaining to the full allowance', () {
      final clock = FakeClock(today: DateTime(2026, 10, 23));
      final engine = TimeEngine(clock: clock);
      final yesterday = _session(
        remainingSeconds: 120,
        date: DateTime(2026, 10, 22),
      );

      final s = engine.advance(yesterday, 1000, AllowanceMinutes.fifteen);

      expect(s.remainingSeconds, 900);
      expect(s.date, DateTime(2026, 10, 23));
    });

    test('same day does not reset remaining', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));
      final s = _session(remainingSeconds: 120);

      final s2 = engine.advance(s, 1000, AllowanceMinutes.fifteen);

      expect(s2.remainingSeconds, 119);
      expect(s2.date, DateTime(2026, 10, 23));
    });
  });

  group('thresholdToFire', () {
    test('fires the 10-minute threshold when the session started at 15 minutes',
        () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));

      expect(engine.thresholdToFire(605, 595, 900), 600);
    });

    test('does NOT fire the 15-minute threshold when start was 15 minutes '
        '(threshold equal to start is not strictly below it)', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));

      expect(engine.thresholdToFire(905, 895, 900), isNull);
    });

    test('returns null when no threshold is crossed', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));

      expect(engine.thresholdToFire(700, 650, 900), isNull);
      expect(engine.thresholdToFire(550, 540, 900), isNull);
    });

    test('a 30-minute start fires 15, 10, 5 and each fires exactly once '
        'across a monotonic decline', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));
      const startSec = 1800;

      var remaining = startSec;
      final fired = <int>[];
      while (remaining > 0) {
        final before = remaining;
        remaining = (remaining - 60).clamp(0, startSec); // 1-minute ticks
        final threshold = engine.thresholdToFire(before, remaining, startSec);
        if (threshold != null) fired.add(threshold);
      }

      expect(fired, [900, 600, 300]);
    });

    test('a tick entirely below a threshold does not re-fire it (returns null)',
        () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));

      // Already below the 10-minute threshold; this tick crosses nothing.
      expect(engine.thresholdToFire(595, 535, 1800), isNull);
    });

    test('is pure: re-crossing after added time reports the threshold again; '
        'single-fire enforcement belongs to the caller', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));

      // Parent adds time (remaining back above 600), child plays down again.
      expect(engine.thresholdToFire(650, 590, 1800), 600);
      expect(engine.thresholdToFire(650, 590, 1800), 600);
    });
  });

  group('inLastMinute', () {
    test('at speedFactor 1 the window opens at 60 and closes at 0', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));

      expect(engine.inLastMinute(61), isFalse);
      expect(engine.inLastMinute(60), isTrue);
      expect(engine.inLastMinute(1), isTrue);
      expect(engine.inLastMinute(0), isFalse);
    });

    test('at speedFactor 60 the window is still the final session-minute '
        '(60 session-seconds = 1 wall-second before expiry)', () {
      final engine = TimeEngine(
        clock: FakeClock(today: DateTime(2026, 10, 23)),
        speedFactor: 60,
      );

      expect(engine.inLastMinute(61), isFalse);
      expect(engine.inLastMinute(60), isTrue);
      expect(engine.inLastMinute(1), isTrue);
      expect(engine.inLastMinute(0), isFalse);
    });
  });

  group('thresholdToFire uses plain session units at any speedFactor', () {
    test('at speedFactor 60 thresholds still fire at 600/300 session-seconds',
        () {
      final engine = TimeEngine(
        clock: FakeClock(today: DateTime(2026, 10, 23)),
        speedFactor: 60,
      );

      expect(engine.thresholdToFire(605, 595, 900), 600);
      expect(engine.thresholdToFire(305, 295, 900), 300);
      // Strictly-below-start rule is unchanged by speedFactor.
      expect(engine.thresholdToFire(905, 895, 900), isNull);
    });
  });

  group('applyMasterLock', () {
    test('locking preserves remaining time and marks the session inactive', () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));
      final s = _session(remainingSeconds: 432, active: true);

      final locked = engine.applyMasterLock(
        s,
        locked: true,
        allowance: AllowanceMinutes.fifteen,
      );

      expect(locked.active, isFalse);
      expect(locked.remainingSeconds, 432);
      expect(locked.date, s.date);
    });

    test('unlocking restores the session with the preserved remaining time',
        () {
      final engine = TimeEngine(clock: FakeClock(today: DateTime(2026, 10, 23)));
      final locked = _session(remainingSeconds: 432, active: false);

      final unlocked = engine.applyMasterLock(
        locked,
        locked: false,
        allowance: AllowanceMinutes.fifteen,
      );

      expect(unlocked.active, isTrue);
      expect(unlocked.remainingSeconds, 432);
    });

    test('unlocking after a date rollover grants the full allowance', () {
      final clock = FakeClock(today: DateTime(2026, 10, 23));
      final engine = TimeEngine(clock: clock);
      final locked = _session(
        remainingSeconds: 432,
        date: DateTime(2026, 10, 22),
        active: false,
      );

      final unlocked = engine.applyMasterLock(
        locked,
        locked: false,
        allowance: AllowanceMinutes.fifteen,
      );

      expect(unlocked.active, isTrue);
      expect(unlocked.remainingSeconds, 900);
      expect(unlocked.date, DateTime(2026, 10, 23));
    });
  });

  group('speedFactor 60 (E2E scaling)', () {
    test('a 15-minute allowance expires after 15 wall-seconds', () {
      final engine = TimeEngine(
        clock: FakeClock(today: DateTime(2026, 10, 23)),
        speedFactor: 60,
      );
      var s = _session(remainingSeconds: 900);

      for (var wallSecond = 1; wallSecond <= 15; wallSecond++) {
        s = engine.advance(s, 1000, AllowanceMinutes.fifteen);
        if (wallSecond < 15) {
          expect(s.remainingSeconds, 900 - 60 * wallSecond,
              reason: 'after $wallSecond wall-seconds');
        }
      }

      expect(s.remainingSeconds, 0);
    });
  });
}
