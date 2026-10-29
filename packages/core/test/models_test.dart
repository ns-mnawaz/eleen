import 'package:eleen_core/eleen_core.dart';
import 'package:test/test.dart';

void main() {
  group('AllowanceMinutes', () {
    test('minutes values are 5/15/30/45/60', () {
      expect(AllowanceMinutes.five.minutes, 5);
      expect(AllowanceMinutes.fifteen.minutes, 15);
      expect(AllowanceMinutes.thirty.minutes, 30);
      expect(AllowanceMinutes.fortyFive.minutes, 45);
      expect(AllowanceMinutes.sixty.minutes, 60);
    });

    test('fromMinutes maps valid allowances', () {
      expect(AllowanceMinutes.fromMinutes(5), AllowanceMinutes.five);
      expect(AllowanceMinutes.fromMinutes(15), AllowanceMinutes.fifteen);
      expect(AllowanceMinutes.fromMinutes(30), AllowanceMinutes.thirty);
      expect(AllowanceMinutes.fromMinutes(45), AllowanceMinutes.fortyFive);
      expect(AllowanceMinutes.fromMinutes(60), AllowanceMinutes.sixty);
    });

    test('fromMinutes(20) is null (20-min example from spec is invalid)', () {
      expect(AllowanceMinutes.fromMinutes(20), isNull);
    });

    test('fromMinutes returns null for other invalid values', () {
      expect(AllowanceMinutes.fromMinutes(0), isNull);
      expect(AllowanceMinutes.fromMinutes(90), isNull);
    });
  });

  group('Profile', () {
    test('holds its fields', () {
      final p = Profile(
        id: 'p1',
        name: 'Alice',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );
      expect(p.id, 'p1');
      expect(p.name, 'Alice');
      expect(p.avatar, 'fox');
      expect(p.allowance, AllowanceMinutes.thirty);
      // Existing profiles are child profiles by default.
      expect(p.isParent, isFalse);
    });

    test('isParent defaults to false and can be set', () {
      const child = Profile(
        id: 'p1',
        name: 'Alice',
        avatar: 'fox',
        allowance: AllowanceMinutes.thirty,
      );
      expect(child.isParent, isFalse);

      const parent = Profile(
        id: 'p2',
        name: 'Ava',
        avatar: 'bear',
        allowance: AllowanceMinutes.thirty,
        isParent: true,
      );
      expect(parent.isParent, isTrue);
    });
  });

  group('SessionState', () {
    test('holds its fields', () {
      final date = DateTime(2026, 10, 23);
      final s = SessionState(
        profileId: 'p1',
        date: date,
        remainingSeconds: 1800,
        active: true,
      );
      expect(s.profileId, 'p1');
      expect(s.date, date);
      expect(s.remainingSeconds, 1800);
      expect(s.active, isTrue);
    });
  });

  group('TvState', () {
    test('defaults masterLockEnabled to false', () {
      final tv = TvState(
        profiles: const [],
        activeSession: null,
        remainingByProfile: const {},
      );
      expect(tv.masterLockEnabled, isFalse);
    });

    test('holds its fields', () {
      final p = Profile(
        id: 'p1',
        name: 'Alice',
        avatar: 'fox',
        allowance: AllowanceMinutes.fifteen,
      );
      final s = SessionState(
        profileId: 'p1',
        date: DateTime(2026, 10, 23),
        remainingSeconds: 900,
        active: true,
      );
      final tv = TvState(
        profiles: [p],
        activeSession: s,
        masterLockEnabled: true,
        remainingByProfile: {'p1': 900},
      );
      expect(tv.profiles, [p]);
      expect(tv.activeSession, s);
      expect(tv.masterLockEnabled, isTrue);
      expect(tv.remainingByProfile, {'p1': 900});
    });
  });

  group('Settings', () {
    test('holds its fields', () {
      final s = Settings(parentPin: '1234', token: 'tok');
      expect(s.parentPin, '1234');
      expect(s.token, 'tok');
      expect(s.masterLockEnabled, isFalse);
    });
  });
}
