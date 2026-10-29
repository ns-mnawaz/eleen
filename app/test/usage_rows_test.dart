// Phone dashboard usage lines (v1.1 D): child rows show "Used today" (next
// to the remaining line) plus a "Yesterday" line when present; parent rows
// show usage as THEIR line (no remaining row); a payload without usage
// (older server) simply renders no usage lines.

import 'package:eleen/phone/profiles_screen.dart';
import 'package:eleen/state/phone_controller.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements EleenOps {
  _FakeClient(this.nextState);

  TvState nextState;

  @override
  Future<TvState> state() async => nextState;

  @override
  Future<void> addTime(String profileId, int addSeconds, String pin) async {}

  @override
  Future<void> overrideTime(
      String profileId, int remainingSeconds, String pin) async {}

  @override
  Future<void> setMasterLock(bool enabled, String pin) async {}

  @override
  Future<void> upsertProfile(Profile profile, String pin) async {}
}

TvState _state({
  Map<String, ProfileUsage> usage = const {},
  List<Profile> profiles = const [],
}) =>
    TvState(
      profiles: profiles,
      activeSession: null,
      remainingByProfile: {
        for (final p in profiles) p.id: p.allowance.minutes * 60,
      },
      usageByProfile: usage,
    );

const kid = Profile(
  id: 'kid',
  name: 'Maya',
  avatar: 'fox',
  allowance: AllowanceMinutes.fifteen,
);

const parent = Profile(
  id: 'parent',
  name: 'Ava',
  avatar: 'bear',
  allowance: AllowanceMinutes.thirty,
  isParent: true,
);

void main() {
  // History dates are derived from the real clock (normalized to the day),
  // never hardcoded: a fixed date drifts from "today" to "yesterday" as the
  // wall clock passes it and flips these expectations.
  final now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);
  final DateTime yesterday = today.subtract(const Duration(days: 1));

  testWidgets('child row shows "Used today" next to the remaining line',
      (tester) async {
    final client = _FakeClient(_state(profiles: const [kid], usage: {
      'kid': ProfileUsage(
        todaySeconds: 1500,
        history: [DayUsage(date: today, seconds: 1500)],
      ),
    }));

    await tester.pumpWidget(
        MaterialApp(home: ProfilesScreen(client: client)));
    await tester.pump();

    expect(find.textContaining('15:00 left'), findsOneWidget);
    expect(find.textContaining('Used today: 25 min'), findsOneWidget);
    // No usage yesterday in this payload.
    expect(find.textContaining('Yesterday'), findsNothing);
  });

  testWidgets('child row shows a "Yesterday" history line when present',
      (tester) async {
    final client = _FakeClient(_state(profiles: const [kid], usage: {
      'kid': ProfileUsage(
        todaySeconds: 1500,
        history: [
          DayUsage(date: today, seconds: 1500),
          DayUsage(date: yesterday, seconds: 1800),
        ],
      ),
    }));

    await tester.pumpWidget(
        MaterialApp(home: ProfilesScreen(client: client)));
    await tester.pump();

    expect(find.textContaining('Used today: 25 min'), findsOneWidget);
    expect(find.textContaining('Yesterday: 30 min'), findsOneWidget);
  });

  testWidgets('parent row shows usage instead of a remaining line',
      (tester) async {
    final client = _FakeClient(_state(profiles: const [parent], usage: {
      'parent': ProfileUsage(
        todaySeconds: 7200,
        history: [DayUsage(date: today, seconds: 7200)],
      ),
    }));

    await tester.pumpWidget(
        MaterialApp(home: ProfilesScreen(client: client)));
    await tester.pump();

    expect(find.textContaining('Used today: 120 min'), findsOneWidget);
    // Parents have no remaining-time line at all.
    expect(find.textContaining('left'), findsNothing);
    expect(find.textContaining('Allowance'), findsNothing);
  });

  testWidgets('a payload without usage (older server) renders no usage '
      'lines and nothing throws', (tester) async {
    final client = _FakeClient(_state(profiles: const [kid, parent]));

    await tester.pumpWidget(
        MaterialApp(home: ProfilesScreen(client: client)));
    await tester.pump();

    expect(find.textContaining('Used today'), findsNothing);
    expect(find.textContaining('Yesterday'), findsNothing);
    // The plain rows still render.
    expect(find.textContaining('15:00 left'), findsOneWidget);
    expect(find.text('Parent profile'), findsOneWidget);
  });

  testWidgets('the live ticker preserves usage between polls', (tester) async {
    // Regression: the controller's between-poll tick used to rebuild the
    // state without the usage map (and parentPinSet), blanking the lines
    // every second while a session runs.
    final client = _FakeClient(_state(
      profiles: const [kid],
      usage: {
        'kid': ProfileUsage(
          todaySeconds: 1500,
          history: [DayUsage(date: today, seconds: 1500)],
        ),
      },
    ));
    final controller = PhoneController(
      client: client,
      pollInterval: const Duration(hours: 1),
    );

    await tester.pumpWidget(
        MaterialApp(home: ProfilesScreen(controller: controller, client: client)));
    await tester.pump();
    expect(find.textContaining('Used today: 25 min'), findsOneWidget);

    // Simulate the active session's live countdown tick.
    controller.tickForTest();
    await tester.pump();

    expect(find.textContaining('Used today: 25 min'), findsOneWidget);
    controller.dispose();
  });
}
