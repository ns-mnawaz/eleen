// Phone profiles dashboard tests: the controller (polling, offline
// mapping, live remaining) and the screen (rows, add-time, override,
// allowance editor, master lock). Every client is a fake — no sockets.

import 'dart:async';
import 'dart:io';

import 'package:eleen/phone/profiles_screen.dart';
import 'package:eleen/phone/widgets/pin_dialog.dart';
import 'package:eleen/state/phone_controller.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [EleenOps]: records every call, serves a canned [TvState],
/// and can be told to fail each operation. Never opens a socket.
class _FakeClient implements EleenOps {
  TvState? nextState;
  Object? stateError;

  /// When set, [state] blocks on it (simulates a fetch in flight).
  Completer<TvState>? stateGate;
  int stateCalls = 0;

  Object? addTimeError;
  final List<(String, int, String)> addTimeCalls = [];

  Object? overrideTimeError;
  final List<(String, int, String)> overrideTimeCalls = [];

  Object? setMasterLockError;
  final List<(bool, String)> setMasterLockCalls = [];

  Object? upsertProfileError;
  final List<(Profile, String)> upsertProfileCalls = [];

  @override
  Future<TvState> state() async {
    stateCalls++;
    final gate = stateGate;
    if (gate != null) return gate.future;
    if (stateError != null) throw stateError!;
    return nextState!;
  }

  @override
  Future<void> addTime(String profileId, int addSeconds, String pin) async {
    addTimeCalls.add((profileId, addSeconds, pin));
    if (addTimeError != null) throw addTimeError!;
  }

  @override
  Future<void> overrideTime(
      String profileId, int remainingSeconds, String pin) async {
    overrideTimeCalls.add((profileId, remainingSeconds, pin));
    if (overrideTimeError != null) throw overrideTimeError!;
  }

  @override
  Future<void> setMasterLock(bool enabled, String pin) async {
    setMasterLockCalls.add((enabled, pin));
    if (setMasterLockError != null) throw setMasterLockError!;
    // The server would apply it; mirror it so the controller's post-success
    // refresh sees the new lock state.
    final st = nextState;
    if (st != null) {
      nextState = TvState(
        profiles: st.profiles,
        activeSession: st.activeSession,
        masterLockEnabled: enabled,
        remainingByProfile: st.remainingByProfile,
      );
    }
  }

  @override
  Future<void> upsertProfile(Profile profile, String pin) async {
    upsertProfileCalls.add((profile, pin));
    if (upsertProfileError != null) throw upsertProfileError!;
    final st = nextState;
    if (st != null) {
      // Server contract: an empty id is a create (the server assigns the
      // id); a non-empty id patches in place.
      if (profile.id.isEmpty) {
        final assigned = Profile(
          id: 'new-${upsertProfileCalls.length}',
          name: profile.name,
          avatar: profile.avatar,
          allowance: profile.allowance,
          isParent: profile.isParent,
        );
        nextState = TvState(
          profiles: [...st.profiles, assigned],
          activeSession: st.activeSession,
          masterLockEnabled: st.masterLockEnabled,
          parentPinSet: st.parentPinSet,
          remainingByProfile: {
            ...st.remainingByProfile,
            assigned.id: assigned.allowance.minutes * 60,
          },
        );
        return;
      }
      nextState = TvState(
        profiles: [
          for (final p in st.profiles) p.id == profile.id ? profile : p,
        ],
        activeSession: st.activeSession,
        masterLockEnabled: st.masterLockEnabled,
        parentPinSet: st.parentPinSet,
        remainingByProfile: st.remainingByProfile,
      );
    }
  }
}

const _maya = Profile(
    id: 'p1', name: 'Maya', avatar: 'M', allowance: AllowanceMinutes.thirty);

const _ava = Profile(
    id: 'pa',
    name: 'Ava',
    avatar: 'B',
    allowance: AllowanceMinutes.thirty,
    isParent: true);

/// Child + parent rows, child session active. A PIN is set: the PIN-gated
/// flows show the dialog (the no-PIN skip variants use their own states).
TvState _tvStateWithParent({int remaining = 300}) => TvState(
      profiles: const [_maya, _ava],
      activeSession: SessionState(
        profileId: 'p1',
        date: DateTime(2026, 10, 23),
        remainingSeconds: remaining,
        active: true,
      ),
      parentPinSet: true,
      remainingByProfile: {'p1': remaining, 'pa': 30 * 60},
    );

TvState _tvState({bool masterLock = false, int remaining = 300,
      bool overlayGranted = true}) => TvState(
      profiles: const [_maya],
      activeSession: SessionState(
        profileId: 'p1',
        date: DateTime(2026, 10, 23),
        remainingSeconds: remaining,
        active: true,
      ),
      masterLockEnabled: masterLock,
      // A PIN is set: the PIN-gated flows show the dialog (the no-PIN skip
      // variants use their own states).
      parentPinSet: true,
      remainingByProfile: {'p1': remaining},
      overlayPermissionGranted: overlayGranted,
    );

/// Long pollInterval so the periodic timer never fires mid-test; the 1s
/// live-remaining ticker is what pump(duration) drives.
const _noPoll = Duration(hours: 1);

Future<void> _pumpScreen(WidgetTester tester, _FakeClient client) async {
  await tester.pumpWidget(MaterialApp(
      home: ProfilesScreen(client: client, pollInterval: _noPoll)));
  // Flush the controller's initial fetch, then rebuild with the result.
  await tester.pump();
  await tester.pump();
}

Future<String> _submitPin(WidgetTester tester, String pin) async {
  await tester.enterText(find.byKey(const Key('pin-field')), pin);
  await tester.tap(find.byKey(const Key('pin-submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return pin;
}

void main() {
  group('PhoneController', () {
    testWidgets('fetches immediately and exposes the state', (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      final controller = PhoneController(
          client: client, pollInterval: const Duration(hours: 1));

      expect(controller.state, isNull);
      await tester.pump();

      expect(client.stateCalls, 1);
      expect(controller.state, isNotNull);
      expect(controller.state!.profiles.first.name, 'Maya');
      expect(controller.offline, isFalse);
      controller.dispose();
    });

    testWidgets('maps offline failures to the offline flag and keeps the '
        'last good state', (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      final controller = PhoneController(
          client: client, pollInterval: const Duration(hours: 1));
      await tester.pump();
      expect(controller.offline, isFalse);

      client.stateError = EleenOffline(const SocketException('refused'));
      await controller.refresh();
      await tester.pump();
      expect(controller.offline, isTrue);
      expect(controller.state, isNotNull, reason: 'last good state retained');

      client.stateError = const HttpException('connection closed');
      await controller.refresh();
      await tester.pump();
      expect(controller.offline, isTrue);

      client.stateError = const EleenApiError(500);
      await controller.refresh();
      await tester.pump();
      expect(controller.offline, isFalse, reason: '401/500 is not offline');
      expect(controller.error, isNotNull);
      controller.dispose();
    });

    testWidgets('polls every pollInterval', (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      final controller = PhoneController(
          client: client, pollInterval: const Duration(seconds: 5));
      await tester.pump();
      expect(client.stateCalls, 1);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(client.stateCalls, 2);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(client.stateCalls, 4);
      controller.dispose();
    });

    testWidgets('a fetch in flight at dispose must not notify afterwards',
        (tester) async {
      final gate = Completer<TvState>();
      final client = _FakeClient()..stateGate = gate;
      final controller = PhoneController(
          client: client, pollInterval: const Duration(hours: 1));
      await tester.pump();

      controller.dispose();
      gate.complete(_tvState());
      await tester.pump();
      expect(tester.takeException(), isNull);

      final errorGate = Completer<TvState>();
      final client2 = _FakeClient()..stateGate = errorGate;
      final controller2 = PhoneController(
          client: client2, pollInterval: const Duration(hours: 1));
      await tester.pump();
      controller2.dispose();
      errorGate.completeError(EleenOffline(const SocketException('refused')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('delegates addTime/overrideTime/setMasterLock/upsertProfile '
        'and refreshes on success', (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      final controller = PhoneController(
          client: client, pollInterval: const Duration(hours: 1));
      await tester.pump();
      final before = client.stateCalls;

      await controller.addTime('p1', 900, '1234');
      await controller.overrideTime('p1', 600, '1234');
      await controller.setMasterLock(true, '1234');
      await controller.upsertProfile(_maya, '1234');

      expect(client.addTimeCalls, [('p1', 900, '1234')]);
      expect(client.overrideTimeCalls, [('p1', 600, '1234')]);
      expect(client.setMasterLockCalls, [(true, '1234')]);
      expect(client.upsertProfileCalls, [(_maya, '1234')]);
      expect(client.stateCalls, greaterThan(before));
      controller.dispose();
    });
  });

  group('ProfilesScreen', () {
    testWidgets('rows render name, allowance chip and live remaining m:ss',
        (tester) async {
      await _pumpScreen(tester, _FakeClient()..nextState = _tvState());

      expect(find.text('Maya'), findsOneWidget);
      expect(find.textContaining('Allowance 30 min'), findsOneWidget);
      expect(find.textContaining('5:00 left'), findsOneWidget);

      // The live ticker counts down between polls.
      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining('4:58 left'), findsOneWidget);
    });

    testWidgets('offline state shows the banner', (tester) async {
      final client = _FakeClient()
        ..nextState = _tvState()
        ..stateError = EleenOffline(const SocketException('refused'));
      await _pumpScreen(tester, client);

      expect(
          find.text('TV offline — check both devices are on the same Wi-Fi'),
          findsOneWidget);
    });

    testWidgets('add-time flow: PIN dialog then amount, calls addTime',
        (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      await _pumpScreen(tester, client);

      await tester.tap(find.text('Add time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No call until the PIN has been entered and an amount picked.
      expect(find.byKey(const Key('pin-field')), findsOneWidget);
      expect(client.addTimeCalls, isEmpty);

      await _submitPin(tester, '1234');
      expect(find.byKey(const Key('pin-field')), findsNothing);

      await tester.tap(find.byKey(const Key('add-amount-30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.addTimeCalls, [('p1', 30 * 60, '1234')]);
      // Dialog closed on success.
      expect(find.byKey(const Key('add-amounts')), findsNothing);
    });

    testWidgets('wrong PIN (403) shows an error and the dialog stays open',
        (tester) async {
      final client = _FakeClient()
        ..nextState = _tvState()
        ..addTimeError = const EleenApiError(403, 'wrong pin');
      await _pumpScreen(tester, client);

      await tester.tap(find.text('Add time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _submitPin(tester, '0000');
      await tester.tap(find.byKey(const Key('add-amount-15')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.addTimeCalls, [('p1', 15 * 60, '0000')]);
      expect(find.text('Wrong PIN'), findsOneWidget);
      // Stay: the amount dialog is still up for a retry.
      expect(find.byKey(const Key('add-amounts')), findsOneWidget);
    });

    testWidgets('offline add-time surfaces the offline copy, stays open',
        (tester) async {
      final client = _FakeClient()
        ..nextState = _tvState()
        ..addTimeError = EleenOffline(const SocketException('refused'));
      await _pumpScreen(tester, client);

      await tester.tap(find.text('Add time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _submitPin(tester, '1234');
      await tester.tap(find.byKey(const Key('add-amount-15')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
          find.text('TV offline — check both devices are on the same Wi-Fi'),
          findsOneWidget);
      expect(find.byKey(const Key('add-amounts')), findsOneWidget);
    });

    testWidgets('override flow: PIN dialog then minute-picker, calls '
        'overrideTime', (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      await _pumpScreen(tester, client);

      await tester.tap(find.text('Override'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _submitPin(tester, '4321');
      await tester.tap(find.byKey(const Key('override-minutes-10')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.overrideTimeCalls, [('p1', 10 * 60, '4321')]);
      expect(find.byKey(const Key('override-picker')), findsNothing);
    });

    testWidgets('master lock toggle requires the PIN before setMasterLock',
        (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      await _pumpScreen(tester, client);

      await tester.tap(find.byKey(const Key('master-lock-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Dialog open, nothing sent yet.
      expect(find.byKey(const Key('pin-field')), findsOneWidget);
      expect(client.setMasterLockCalls, isEmpty);

      // Back out without a PIN: still nothing sent.
      await tester.tap(find.byKey(const Key('pin-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(client.setMasterLockCalls, isEmpty);

      // Now with the PIN.
      await tester.tap(find.byKey(const Key('master-lock-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _submitPin(tester, '9876');
      await tester.pump();

      expect(client.setMasterLockCalls, [(true, '9876')]);
      // The refreshed state shows the lock as on.
      final switchTile = tester.widget<SwitchListTile>(
          find.byKey(const Key('master-lock-switch')));
      expect(switchTile.value, isTrue);
    });

    testWidgets('master lock on dims the rows with a lock icon',
        (tester) async {
      await _pumpScreen(
          tester, _FakeClient()..nextState = _tvState(masterLock: true));

      expect(find.byIcon(Icons.lock), findsWidgets);
      final opacity = tester
          .widget<Opacity>(find.byKey(const Key('profile-row-p1-dim')));
      expect(opacity.opacity, lessThan(1));
    });

    testWidgets('long-press opens the allowance editor behind the PIN and '
        'calls upsertProfile', (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      await _pumpScreen(tester, client);

      await tester.longPress(find.byKey(const Key('profile-row-p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _submitPin(tester, '1111');
      await tester.tap(find.byKey(const Key('allowance-45')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.upsertProfileCalls, hasLength(1));
      final (profile, pin) = client.upsertProfileCalls.single;
      expect(pin, '1111');
      expect(profile.id, 'p1');
      expect(profile.name, 'Maya');
      expect(profile.allowance, AllowanceMinutes.fortyFive);
      // The refreshed row shows the new allowance.
      expect(find.textContaining('Allowance 45 min'), findsOneWidget);
    });

    testWidgets('PIN dialog rejects an empty PIN without calling anything',
        (tester) async {
      final client = _FakeClient()..nextState = _tvState();
      await _pumpScreen(tester, client);

      await tester.tap(find.text('Add time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const Key('pin-submit')));
      await tester.pump();

      // Still open, still nothing sent.
      expect(find.byKey(const Key('pin-field')), findsOneWidget);
      expect(client.addTimeCalls, isEmpty);
    });
  });

  group('ProfilesScreen TV overlay permission hint', () {
    testWidgets('TV missing the overlay permission: warning hint shown; '
        'granted: nothing', (tester) async {
      final client = _FakeClient()..nextState = _tvState(overlayGranted: false);
      final controller = PhoneController(
          client: client, pollInterval: _noPoll);
      await tester.pumpWidget(MaterialApp(
          home: ProfilesScreen(client: client, controller: controller)));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('tv-overlay-permission-denied')),
          findsOneWidget);
      expect(find.textContaining("can't lock other apps"), findsOneWidget);

      // The TV grants it; the next refresh clears the hint.
      client.nextState = _tvState(overlayGranted: true);
      await controller.refresh();
      await tester.pump();
      expect(find.byKey(const Key('tv-overlay-permission-denied')),
          findsNothing);
      expect(find.byKey(const Key('tv-overlay-permission-allowed')),
          findsOneWidget,
          reason: 'the shrink placeholder keeps a stable negative key');
      controller.dispose();
    });
  });

  group('ProfilesScreen create profile', () {
    TvState emptyTvState() => const TvState(
          profiles: [],
          activeSession: null,
          parentPinSet: true,
          remainingByProfile: {},
        );

    Future<void> openForm(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('add-profile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('fresh state: FAB -> form -> PIN -> create with an empty id '
        'and the row appears', (tester) async {
      final client = _FakeClient()..nextState = emptyTvState();
      await _pumpScreen(tester, client);

      await openForm(tester);
      await tester.enterText(find.byKey(const Key('create-name')), 'Leo');
      await tester.tap(find.byKey(const Key('avatar-choice-2')));
      await tester.tap(find.byKey(const Key('create-allowance-45')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The PIN confirmation is on top; nothing sent yet.
      expect(find.byKey(const Key('pin-field')), findsOneWidget);
      expect(client.upsertProfileCalls, isEmpty);

      await _submitPin(tester, '1234');
      await tester.pump();

      expect(client.upsertProfileCalls, hasLength(1));
      final (profile, pin) = client.upsertProfileCalls.single;
      expect(pin, '1234');
      expect(profile.id, isEmpty, reason: 'empty id = create; server assigns');
      expect(profile.name, 'Leo');
      expect(profile.avatar, kAvatarChoices[2]);
      expect(profile.allowance, AllowanceMinutes.fortyFive);

      // The controller refreshed; the new row is on the dashboard and both
      // dialogs are closed.
      expect(find.byKey(const Key('profile-row-new-1')), findsOneWidget);
      expect(find.byKey(const Key('create-profile')), findsNothing);
      expect(find.byKey(const Key('pin-field')), findsNothing);
    });

    testWidgets('create requires a name before the PIN step', (tester) async {
      final client = _FakeClient()..nextState = emptyTvState();
      await _pumpScreen(tester, client);

      await openForm(tester);
      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pump();

      expect(find.text('Enter a name'), findsOneWidget);
      expect(find.byKey(const Key('pin-field')), findsNothing);
      expect(client.upsertProfileCalls, isEmpty);
    });

    testWidgets('a wrong PIN (403) keeps the PIN dialog up, nothing created '
        'until it succeeds', (tester) async {
      final client = _FakeClient()
        ..nextState = emptyTvState()
        ..upsertProfileError = const EleenApiError(403, 'wrong pin');
      await _pumpScreen(tester, client);

      await openForm(tester);
      await tester.enterText(find.byKey(const Key('create-name')), 'Leo');
      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _submitPin(tester, '0000');
      await tester.pump();

      // The PIN dialog stayed open with the server's verdict; the create
      // dialog is still beneath it.
      expect(find.text('Wrong PIN'), findsOneWidget);
      expect(find.byKey(const Key('pin-field')), findsOneWidget);
      expect(find.byKey(const Key('create-profile')), findsOneWidget);

      // Retry with the right PIN: succeeds, both dialogs close.
      client.upsertProfileError = null;
      await tester.enterText(find.byKey(const Key('pin-field')), '1234');
      await tester.tap(find.byKey(const Key('pin-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      expect(find.byKey(const Key('create-profile')), findsNothing);
      expect(find.byKey(const Key('profile-row-new-2')), findsOneWidget);
    });
  });

  group('ProfilesScreen with no PIN set', () {
    TvState noPinState({bool masterLock = false}) => TvState(
          profiles: const [_maya],
          activeSession: SessionState(
            profileId: 'p1',
            date: DateTime(2026, 10, 23),
            remainingSeconds: 300,
            active: true,
          ),
          masterLockEnabled: masterLock,
          parentPinSet: false,
          remainingByProfile: {'p1': 300},
        );

    testWidgets('add-time skips the PIN dialog and forwards the empty pin',
        (tester) async {
      final client = _FakeClient()..nextState = noPinState();
      await _pumpScreen(tester, client);

      await tester.tap(find.text('Add time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Straight to the amount picker — no PIN step.
      expect(find.byKey(const Key('pin-field')), findsNothing);
      expect(find.byKey(const Key('add-amounts')), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-amount-30')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.addTimeCalls, [('p1', 30 * 60, '')]);
      expect(find.byKey(const Key('add-amounts')), findsNothing);
    });

    testWidgets('override skips the PIN dialog and forwards the empty pin',
        (tester) async {
      final client = _FakeClient()..nextState = noPinState();
      await _pumpScreen(tester, client);

      await tester.tap(find.text('Override'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('pin-field')), findsNothing);
      expect(find.byKey(const Key('override-picker')), findsOneWidget);

      await tester.tap(find.byKey(const Key('override-minutes-10')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.overrideTimeCalls, [('p1', 10 * 60, '')]);
    });

    testWidgets('master lock applies directly without a PIN dialog',
        (tester) async {
      final client = _FakeClient()..nextState = noPinState();
      await _pumpScreen(tester, client);

      await tester.tap(find.byKey(const Key('master-lock-switch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('pin-field')), findsNothing);
      expect(client.setMasterLockCalls, [(true, '')]);
    });

    testWidgets('profile creation submits without a PIN dialog',
        (tester) async {
      final client = _FakeClient()
        ..nextState = const TvState(
            profiles: [],
            activeSession: null,
            parentPinSet: false,
            remainingByProfile: {});
      await _pumpScreen(tester, client);

      await tester.tap(find.byKey(const Key('add-profile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byKey(const Key('create-name')), 'Leo');
      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('pin-field')), findsNothing);
      expect(client.upsertProfileCalls, hasLength(1));
      expect(client.upsertProfileCalls.single.$2, isEmpty);
      // Both dialogs closed on success.
      expect(find.byKey(const Key('create-profile')), findsNothing);
    });
  });

  group('ProfilesScreen legacy parent rows', () {
    testWidgets('parent rows show a Parent badge, no remaining line and no '
        'Add time/Override buttons', (tester) async {
      await _pumpScreen(
          tester, _FakeClient()..nextState = _tvStateWithParent());

      final parentRow = find.byKey(const Key('profile-row-pa'));
      expect(find.descendant(of: parentRow, matching: find.text('Parent')),
          findsOneWidget);
      // Same lock icon as the TV's Parent badge.
      expect(find.descendant(of: parentRow, matching: find.byIcon(Icons.lock)),
          findsOneWidget);
      // No "mm:ss left" on the parent row (the child row still has one).
      expect(
          find.descendant(
              of: parentRow, matching: find.textContaining('left')),
          findsNothing);
      expect(find.textContaining('5:00 left'), findsOneWidget);
      expect(find.textContaining('30:00 left'), findsNothing);

      // No per-row time controls for a parent.
      expect(
          find.descendant(of: parentRow, matching: find.text('Add time')),
          findsNothing);
      expect(
          find.descendant(of: parentRow, matching: find.text('Override')),
          findsNothing);
      // The child row keeps its buttons.
      expect(find.text('Add time'), findsOneWidget);
      expect(find.text('Override'), findsOneWidget);
    });

    testWidgets('create form is child-only: no Parent toggle, allowance '
        'chips always visible, submits isParent false', (tester) async {
      final client = _FakeClient()
        ..nextState = const TvState(
            profiles: [],
            activeSession: null,
            parentPinSet: true,
            remainingByProfile: {});
      await _pumpScreen(tester, client);

      await tester.tap(find.byKey(const Key('add-profile')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // No parent-type editor any more; the allowance chips are always up.
      expect(find.byKey(const Key('create-parent-toggle')), findsNothing);
      expect(find.byKey(const Key('create-allowance-45')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('create-name')), 'Nia');
      await tester.tap(find.byKey(const Key('create-allowance-45')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await _submitPin(tester, '1234');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(client.upsertProfileCalls, hasLength(1));
      final (profile, pin) = client.upsertProfileCalls.single;
      expect(pin, '1234');
      expect(profile.name, 'Nia');
      expect(profile.isParent, isFalse);
      expect(profile.allowance, AllowanceMinutes.fortyFive);
    });
  });

  group('PinDialog', () {
    testWidgets('show() pops with the entered PIN', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            result = await PinDialog.show(context, title: 'Enter parent PIN');
          },
          child: const Text('open'),
        );
      })));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(find.byKey(const Key('pin-field')), '2468');
      await tester.tap(find.byKey(const Key('pin-submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(result, '2468');
    });

    testWidgets('show() with pinSet false skips the dialog and pops the '
        'empty pin', (tester) async {
      String? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            result = await PinDialog.show(context,
                title: 'Enter parent PIN', pinSet: false);
          },
          child: const Text('open'),
        );
      })));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('pin-field')), findsNothing);
      expect(result, '');
    });

    testWidgets('run() with pinSet false runs the action with the empty pin '
        'and pops true', (tester) async {
      String? submitted;
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
        return TextButton(
          onPressed: () async {
            result = await PinDialog.run(context,
                title: 'Enter parent PIN', pinSet: false,
                onSubmit: (pin) async => submitted = pin);
          },
          child: const Text('open'),
        );
      })));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const Key('pin-field')), findsNothing);
      expect(submitted, '');
      expect(result, isTrue);
    });

    testWidgets('run() with pinSet false surfaces a failure via a snackbar '
        'and pops false', (tester) async {
      bool? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: Builder(builder: (context) {
          return TextButton(
            onPressed: () async {
              result = await PinDialog.run(context,
                  title: 'Enter parent PIN', pinSet: false,
                  onSubmit: (pin) async =>
                      throw const EleenApiError(403, 'wrong pin'));
            },
            child: const Text('open'),
          );
        }),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(result, isFalse);
      expect(find.text('Wrong PIN'), findsOneWidget,
          reason: 'the failure is still surfaced, via a snackbar');
    });
  });
}
