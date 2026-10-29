// TV-side profile management at the controller level: creating and editing
// profiles through the same [EngineCoordinator] paths the HTTP routes use,
// so the phone sees TV-made changes on its next poll.
//
// Editing must preserve the profile's session (remaining time / active
// flag): patchProfile only rewrites the profile row.

import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic [Clock] so seeded sessions always match "today".
class _FakeClock implements Clock {
  _FakeClock(this.date);

  final DateTime date;

  @override
  int nowMs() => 0;

  @override
  DateTime today() => date;
}

void main() {
  final today = DateTime(2026, 10, 24);

  late EleenDatabase db;
  late TvController controller;

  setUp(() {
    db = EleenDatabase(NativeDatabase.memory());
    controller = TvController(
      db: db,
      clock: _FakeClock(today),
      speedFactor: 1,
    );
  });

  tearDown(() async {
    controller.dispose();
    await db.close();
  });

  Future<void> seedKid() async {
    await db.upsertProfile(const Profile(
      id: 'kid',
      name: 'Maya',
      avatar: 'fox',
      allowance: AllowanceMinutes.thirty,
    ));
    await controller.refresh();
  }

  test('creating a profile through the coordinator adds it to the '
      'controller (the phone sees it on its next poll)', () async {
    await seedKid();

    final created = await controller.coordinator.createProfile(
      name: 'Nia',
      avatar: '★',
      allowance: AllowanceMinutes.fifteen,
    );
    await controller.refresh();

    expect(controller.profiles.where((p) => p.id == created.id).first.name,
        'Nia');
    expect(controller.profiles.where((p) => p.id == created.id).first.allowance,
        AllowanceMinutes.fifteen);
    expect(controller.profiles.where((p) => p.id == created.id).first.isParent,
        isFalse);
    // The same state the server would hand the phone.
    final serverState = await controller.coordinator.state();
    expect(serverState.profiles.where((p) => p.name == 'Nia'), hasLength(1));
  });

  test('creating a parent profile through the coordinator sets isParent',
      () async {
    await seedKid();

    await controller.coordinator.createProfile(
      name: 'Ava',
      avatar: '♥',
      allowance: AllowanceMinutes.thirty,
      isParent: true,
    );
    await controller.refresh();

    expect(
        controller.profiles.where((p) => p.name == 'Ava').first.isParent,
        isTrue);
  });

  test('patching a profile updates name and allowance and PRESERVES the '
      'session (remaining seconds + active flag)', () async {
    await seedKid();
    // An in-flight session: 5 minutes left, active.
    await db.saveSession(SessionState(
      profileId: 'kid',
      date: today,
      remainingSeconds: 300,
      active: true,
    ));

    final updated = await controller.coordinator.patchProfile(
      'kid',
      name: 'Maya B.',
      allowance: AllowanceMinutes.fifteen,
    );
    await controller.refresh();

    expect(updated, isNotNull);
    expect(updated!.name, 'Maya B.');
    expect(updated.allowance, AllowanceMinutes.fifteen);
    expect(updated.id, 'kid', reason: 'patch keeps the id: same profile row');

    // The untouched session: editing a profile must not reset or drop it.
    final session = await db.sessionForProfile('kid', today);
    expect(session, isNotNull);
    expect(session!.remainingSeconds, 300);
    expect(session.active, isTrue);
    // And the controller state still reports the preserved remainder.
    expect(controller.state!.remainingByProfile['kid'], 300);
  });

  test('patching an unknown profile returns null and changes nothing',
      () async {
    await seedKid();

    final updated = await controller.coordinator.patchProfile('ghost',
        name: 'Nobody');

    expect(updated, isNull);
    expect(controller.profiles.single.name, 'Maya');
  });
}
