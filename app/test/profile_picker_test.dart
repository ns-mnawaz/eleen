import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen/tv/profile_picker.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {Size size = const Size(800, 600)}) {
  return MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    ),
  );
}

Key cardKey(String profileId) => Key('profile-card-$profileId');

/// Deterministic [Clock] so seeded sessions always match "today", whatever
/// the machine's wall clock says.
class _FakeClock implements Clock {
  _FakeClock(this.date);

  final DateTime date;

  @override
  int nowMs() => 0;

  @override
  DateTime today() => date;
}

void main() {
  final today = DateTime(2026, 10, 23);

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

  Future<void> seedProfiles() async {
    await db.upsertProfile(const Profile(
      id: 'p1',
      name: 'Maya',
      avatar: 'fox',
      allowance: AllowanceMinutes.thirty,
    ));
    await db.upsertProfile(const Profile(
      id: 'p2',
      name: 'Leo',
      avatar: 'lion',
      allowance: AllowanceMinutes.fifteen,
    ));
    await controller.refresh();
  }

  /// Seeds two child profiles plus the parent PIN the management gate
  /// compares against.
  Future<void> seedWithPin({String pin = '1234'}) async {
    await db.saveSettings(Settings(parentPin: pin));
    await db.upsertProfile(const Profile(
      id: 'kid',
      name: 'Maya',
      avatar: 'fox',
      allowance: AllowanceMinutes.thirty,
    ));
    await db.upsertProfile(const Profile(
      id: 'kid2',
      name: 'Leo',
      avatar: 'lion',
      allowance: AllowanceMinutes.fifteen,
    ));
    await controller.refresh();
  }

  Future<void> pumpPicker(WidgetTester tester,
      {Size size = const Size(800, 600)}) async {
    await tester.pumpWidget(_wrap(
      ProfilePicker(controller: controller),
      size: size,
    ));
    await tester.pump();
  }

  testWidgets('picker renders profiles from the seeded controller',
      (WidgetTester tester) async {
    await seedProfiles();
    await pumpPicker(tester);

    expect(find.text('Maya'), findsOneWidget);
    expect(find.text('Leo'), findsOneWidget);
    // Avatar initials.
    expect(find.text('F'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
  });

  testWidgets('picker shows a placeholder when there are no profiles',
      (WidgetTester tester) async {
    await controller.refresh();
    await pumpPicker(tester);

    expect(find.text('No profiles yet'), findsOneWidget);
  });

  testWidgets('D-pad select on the focused cell activates the profile',
      (WidgetTester tester) async {
    await seedProfiles();
    await pumpPicker(tester);

    final activated = controller.stateStream
        .firstWhere((s) => s.activeSession != null);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    final state = await activated;
    expect(state.activeSession, isNotNull);
    expect(state.activeSession!.profileId, 'p1');
    expect(state.activeSession!.active, isTrue);
    // A new session starts at the full allowance: 30 * 60 session seconds.
    expect(state.activeSession!.remainingSeconds, 30 * 60);
  });

  testWidgets('tapping a cell resumes an existing inactive session',
      (WidgetTester tester) async {
    await seedProfiles();
    await db.saveSession(SessionState(
      profileId: 'p1',
      date: today,
      remainingSeconds: 300,
      active: false,
    ));
    await pumpPicker(tester);

    await tester.tap(find.text('Maya'));
    await tester.pumpAndSettle();

    final state = controller.state!;
    expect(state.activeSession, isNotNull);
    expect(state.activeSession!.profileId, 'p1');
    expect(state.activeSession!.active, isTrue);
    // Remaining time is preserved when resuming.
    expect(state.activeSession!.remainingSeconds, 300);
  });

  testWidgets('grid cells derive their size from the available space',
      (WidgetTester tester) async {
    await seedProfiles();

    Future<void> pumpSurface(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(
        ProfilePicker(controller: controller),
        size: size,
      ));
      await tester.pump();
    }

    await pumpSurface(const Size(800, 600));
    final gridSmall = tester.getSize(find.byType(GridView));
    final mayaSmall = tester.getSize(find.byKey(cardKey('p1')));
    final leoSmall = tester.getSize(find.byKey(cardKey('p2')));

    await pumpSurface(const Size(1600, 1200));
    final gridLarge = tester.getSize(find.byType(GridView));
    final mayaLarge = tester.getSize(find.byKey(cardKey('p1')));
    final leoLarge = tester.getSize(find.byKey(cardKey('p2')));

    // The grid fills all of the available space.
    expect(gridSmall, const Size(800, 600));
    expect(gridLarge, const Size(1600, 1200));

    // Doubling the surface doubles the cells: no fixed pixel cell sizes.
    expect(mayaLarge.width, closeTo(mayaSmall.width * 2, 0.01));
    expect(mayaLarge.height, closeTo(mayaSmall.height * 2, 0.01));
    expect(leoLarge.width, closeTo(leoSmall.width * 2, 0.01));
    expect(leoLarge.height, closeTo(leoSmall.height * 2, 0.01));

    // All cells share the same width, and a full row spans the grid width.
    expect(leoSmall.width, closeTo(mayaSmall.width, 0.01));
    final columns = gridSmall.width / mayaSmall.width;
    expect(columns, closeTo(columns.roundToDouble(), 0.01));
  });

  testWidgets('focused cell shows a visible focus border',
      (WidgetTester tester) async {
    await seedProfiles();
    await pumpPicker(tester);

    // The first cell autofocused for D-pad navigation (the card's own
    // detector is the first descendant; the toggle's is out of traversal).
    final fad = tester.widget<FocusableActionDetector>(
      find.descendant(
        of: find.byKey(cardKey('p1')),
        matching: find.byType(FocusableActionDetector),
      ).first,
    );
    expect(fad.focusNode!.hasFocus, isTrue);

    // And the focused cell draws a visible (non-transparent) border.
    final border = tester.widget<Container>(
      find.byKey(Key('profile-card-border-p1')),
    );
    final decoration = border.decoration! as BoxDecoration;
    expect(
      decoration.border!.top.color,
      isNot(Colors.transparent),
    );
  });

  testWidgets('every card carries an "Enforce time" toggle',
      (WidgetTester tester) async {
    await seedProfiles();
    await pumpPicker(tester);

    final toggle = find.byKey(const Key('profile-toggle-p1'));
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isFalse,
        reason: 'nothing enforced yet');
    expect(find.byKey(const Key('profile-toggle-p2')), findsOneWidget);
  });

  testWidgets('toggling enforcement ON with no PIN set starts the session',
      (WidgetTester tester) async {
    await seedProfiles();
    await pumpPicker(tester);

    await tester.tap(find.byKey(const Key('profile-toggle-p1')));
    await tester.pumpAndSettle();

    expect(controller.state!.activeSession, isNotNull);
    expect(controller.state!.activeSession!.profileId, 'p1');
    expect(controller.state!.activeSession!.active, isTrue);
  });

  testWidgets('toggling enforcement OFF ends the active session',
      (WidgetTester tester) async {
    await seedProfiles();
    await pumpPicker(tester);

    await tester.tap(find.byKey(const Key('profile-toggle-p1')));
    await tester.pumpAndSettle();
    expect(controller.state!.activeSession, isNotNull);

    await tester.tap(find.byKey(const Key('profile-toggle-p1')));
    await tester.pumpAndSettle();
    expect(controller.state!.activeSession, isNull);
  });

  testWidgets('enforcing a second profile ends the first (one at a time)',
      (WidgetTester tester) async {
    await seedProfiles();
    await pumpPicker(tester);

    await tester.tap(find.byKey(const Key('profile-toggle-p1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-toggle-p2')));
    await tester.pumpAndSettle();

    expect(controller.state!.activeSession!.profileId, 'p2');
    final p1 = await db.sessionForProfile('p1', today);
    expect(p1!.active, isFalse, reason: 'Maya was deactivated');
    expect(p1.remainingSeconds, 30 * 60, reason: 'her time was preserved');
  });

  testWidgets('with a PIN set, toggling enforcement asks for the PIN first',
      (WidgetTester tester) async {
    await seedWithPin();
    await pumpPicker(tester);

    await tester.tap(find.byKey(const Key('profile-toggle-kid')));
    await tester.pumpAndSettle();

    // The prompt is up and no session has started.
    expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);
    expect(controller.state!.activeSession, isNull);

    // A wrong PIN shows an error and the prompt stays up.
    for (final digit in '9999'.split('')) {
      await tester.tap(find.byKey(Key('pin-key-$digit')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const Key('pin-error')), findsOneWidget);
    expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);
    expect(controller.state!.activeSession, isNull);
  });

  testWidgets('the correct PIN proceeds with the enforcement change',
      (WidgetTester tester) async {
    await seedWithPin();
    await pumpPicker(tester);

    await tester.tap(find.byKey(const Key('profile-toggle-kid')));
    await tester.pumpAndSettle();
    for (final digit in '1234'.split('')) {
      await tester.tap(find.byKey(Key('pin-key-$digit')));
      await tester.pumpAndSettle();
    }

    expect(controller.state!.activeSession, isNotNull);
    expect(controller.state!.activeSession!.profileId, 'kid');
    expect(find.byKey(const Key('parent-pin-prompt')), findsNothing);
  });

  testWidgets('the pad is focused as soon as the toggle gate opens: D-pad '
      'Enter enters digits with no pointer', (WidgetTester tester) async {
    await seedWithPin();
    await pumpPicker(tester);

    await tester.tap(find.byKey(const Key('profile-toggle-kid')));
    await tester.pumpAndSettle();

    String? focusedLabel() {
      for (final node in tester.binding.focusManager.rootScope.descendants) {
        final label = node.debugLabel;
        if (node.hasFocus && label != null && label.startsWith('pin-key-')) {
          return label;
        }
      }
      return null;
    }

    // The '1' cell holds focus right after the prompt opens (the tapped
    // card must not keep it), so arrow-key entry works immediately.
    expect(focusedLabel(), 'pin-key-1');

    // And activating the focused cell types a digit — no tap needed.
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('•'), findsOneWidget);
  });

  testWidgets('tapping a card with a PIN set is gated too',
      (WidgetTester tester) async {
    await seedWithPin();
    await pumpPicker(tester);

    await tester.tap(find.text('Maya'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);
    expect(controller.state!.activeSession, isNull);
  });

  testWidgets('tapping a card with no PIN set starts enforcement directly',
      (WidgetTester tester) async {
    await seedProfiles(); // no settings row: parentPin is empty
    await pumpPicker(tester);

    await tester.tap(find.text('Maya'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('parent-pin-prompt')), findsNothing);
    expect(controller.state!.activeSession, isNotNull);
    expect(controller.state!.activeSession!.profileId, 'p1');
  });

  group('TV profile management', () {
    const addCardKey = Key('add-profile-card');

    /// The debugLabel of the currently focused profile/add-card node, or
    /// null when no such node has the primary focus.
    String? focusedCardLabel(WidgetTester tester) {
      for (final node in tester.binding.focusManager.rootScope.descendants) {
        final label = node.debugLabel;
        if (node.hasFocus &&
            label != null &&
            (label.startsWith('profile-card-') ||
                label.startsWith('add-profile-card'))) {
          return label;
        }
      }
      return null;
    }

    /// Taps the add card and enters the correct PIN on the gate pad (a
    /// wrong PIN first when [wrongFirst]).
    Future<void> openFormViaPin(WidgetTester tester,
        {bool wrongFirst = false}) async {
      await tester.tap(find.byKey(addCardKey));
      await tester.pumpAndSettle();
      if (wrongFirst) {
        for (final digit in '9999'.split('')) {
          await tester.tap(find.byKey(Key('pin-key-$digit')));
          await tester.pumpAndSettle();
        }
      }
      for (final digit in '1234'.split('')) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
    }

    /// Pumps a picker over a fresh controller with NO profiles, so the
    /// empty-picker branch can be asserted.
    Future<void> pumpPickerEmpty(WidgetTester tester) async {
      final emptyDb = EleenDatabase(NativeDatabase.memory());
      final emptyController = TvController(
        db: emptyDb,
        clock: _FakeClock(today),
        speedFactor: 1,
      );
      await emptyController.refresh();
      addTearDown(() async {
        emptyController.dispose();
        await emptyDb.close();
      });
      await tester.pumpWidget(_wrap(ProfilePicker(controller: emptyController)));
      await tester.pump();
    }

    testWidgets('an add-profile card sits last in the grid, after every '
        'profile card', (WidgetTester tester) async {
      await seedProfiles();
      await pumpPicker(tester);

      final addCard = find.byKey(addCardKey);
      expect(addCard, findsOneWidget);
      // Last: to the right of the second profile card (3 columns at this
      // surface size, so p1, p2 and the add card share the first row).
      expect(
        tester.getTopLeft(addCard).dx,
        greaterThan(tester.getTopLeft(find.byKey(cardKey('p2'))).dx),
      );
      // And the empty picker also offers it (no phone-required dead end).
      await pumpPickerEmpty(tester);
      expect(find.text('No profiles yet'), findsOneWidget);
      expect(addCard, findsOneWidget);
    });

    testWidgets('opening the create form requires the parent PIN; a wrong '
        'PIN shows an error and the form does not open',
        (WidgetTester tester) async {
      await seedWithPin();
      await pumpPicker(tester);

      await tester.tap(find.byKey(addCardKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);
      expect(find.byKey(const Key('profile-form')), findsNothing);

      for (final digit in '9999'.split('')) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const Key('pin-error')), findsOneWidget);
      expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget,
          reason: 'the gate stays up for a retry');
      expect(find.byKey(const Key('profile-form')), findsNothing);
      expect(controller.profiles, hasLength(2), reason: 'nothing was created');
    });

    testWidgets('the correct PIN opens the create form',
        (WidgetTester tester) async {
      await seedWithPin();
      await pumpPicker(tester);

      await openFormViaPin(tester);

      expect(find.byKey(const Key('profile-form')), findsOneWidget);
      expect(find.byKey(const Key('parent-pin-prompt')), findsNothing);
    });

    testWidgets('the form does not autofocus the name field: the first '
        'avatar chip holds the initial focus instead, so the system IME '
        'never captures the D-pad on open', (WidgetTester tester) async {
      await seedWithPin();
      await pumpPicker(tester);

      await openFormViaPin(tester);

      final nameField = tester.widget<TextField>(
        find.byKey(const Key('profile-form-name')),
      );
      expect(nameField.focusNode!.hasFocus, isFalse);
      final firstChip = tester.widget<ChoiceChip>(
        find.byKey(const Key('profile-form-avatar-0')),
      );
      expect(firstChip.autofocus, isTrue);
    });

    testWidgets('the form stays usable when the system keyboard is open: '
        'content compresses above it and the Create action stays visible',
        (WidgetTester tester) async {
      await seedWithPin();
      await pumpPicker(tester);
      await openFormViaPin(tester);

      final createFinder = find.byKey(const Key('profile-form-save'));
      expect(createFinder, findsOneWidget);
      final beforeTop = tester.getTopLeft(createFinder).dy;

      // Simulate the system IME: on a TV it takes ~40% of the screen.
      tester.view.viewInsets =
          FakeViewPadding(bottom: tester.view.physicalSize.height * 0.4);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      final createRect = tester.getRect(createFinder);
      final visibleBottom = tester.view.physicalSize.height -
          tester.view.viewInsets.bottom;
      expect(createRect.bottom, lessThanOrEqualTo(visibleBottom),
          reason: 'Create must not hide under the keyboard');
      expect(tester.getTopLeft(createFinder).dy, isNot(equals(beforeTop)),
          reason: 'the form must adapt to the reduced height');
    });

    testWidgets('on a wide TV the form panel occupies the left half, so a '
        'floating keyboard (which never reports insets on Android TV) '
        'cannot cover the actions', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await seedWithPin();
      await pumpPicker(tester);
      await openFormViaPin(tester);

      final saveFinder = find.byKey(const Key('profile-form-save'));
      final saveRect = tester.getRect(saveFinder);
      expect(saveRect.right, lessThanOrEqualTo(1920 * 0.55),
          reason: 'the floating TV keyboard sits center-right; the form '
              'actions must stay in the left zone');
      final nameRect =
          tester.getRect(find.byKey(const Key('profile-form-name')));
      expect(nameRect.right, lessThanOrEqualTo(1920 * 0.55));
    });

    testWidgets('submitting the name with the IME Done key releases the '
        'field and moves focus forward, so D-pad arrows never re-summon '
        'the keyboard in a loop', (WidgetTester tester) async {
      await seedWithPin();
      await pumpPicker(tester);
      await openFormViaPin(tester);

      final nameFinder = find.byKey(const Key('profile-form-name'));
      await tester.enterText(nameFinder, 'Nia');
      expect(
          tester.widget<TextField>(nameFinder).focusNode!.hasFocus, isTrue);

      // The Gboard Done/Enter key.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(
          tester.widget<TextField>(nameFinder).focusNode!.hasFocus, isFalse,
          reason: 'the name field must release focus on Done, otherwise '
              'every arrow key re-shows the keyboard');

      // D-pad right now navigates among chips without touching the field.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
          tester.widget<TextField>(nameFinder).focusNode!.hasFocus, isFalse);
    });

    testWidgets('creating a child profile adds it to the picker with the '
        'chosen allowance', (WidgetTester tester) async {
      await seedWithPin();
      await pumpPicker(tester);

      await openFormViaPin(tester);
      await tester.enterText(find.byKey(const Key('profile-form-name')), 'Nia');
      await tester.pump();
      await tester.tap(find.byKey(const Key('profile-form-allowance-15')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('profile-form-save')));
      await tester.pumpAndSettle();

      // The form closed; the picker shows the new card.
      expect(find.byKey(const Key('profile-form')), findsNothing);
      final created = controller.profiles.where((p) => p.name == 'Nia').toList();
      expect(created, hasLength(1));
      expect(created.single.allowance, AllowanceMinutes.fifteen);
      expect(created.single.isParent, isFalse);
      expect(find.byKey(Key('profile-card-${created.single.id}')),
          findsOneWidget);
    });

    testWidgets('editing pre-fills the form, updates the profile and '
        'preserves the session remaining seconds',
        (WidgetTester tester) async {
      await db.saveSettings(const Settings(parentPin: '1234'));
      await seedProfiles();
      await db.saveSession(SessionState(
        profileId: 'p1',
        date: today,
        remainingSeconds: 300,
        active: false,
      ));
      await pumpPicker(tester);

      // Touch long-press opens the edit gate; PIN admits to the form.
      await tester.longPress(find.text('Maya'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);
      for (final digit in '1234'.split('')) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile-form')), findsOneWidget);
      final nameField = tester.widget<TextField>(
        find.byKey(const Key('profile-form-name')),
      );
      expect(nameField.controller!.text, 'Maya');

      await tester.tap(find.byKey(const Key('profile-form-allowance-15')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('profile-form-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('profile-form')), findsNothing);
      expect(controller.profiles.where((p) => p.id == 'p1').single.allowance,
          AllowanceMinutes.fifteen);
      // The session row was untouched by the profile edit.
      final session = await db.sessionForProfile('p1', today);
      expect(session!.remainingSeconds, 300);
      expect(session.active, isFalse);
    });

    testWidgets('D-pad traversal reaches the add card last, and tapping it '
        'opens the gated form', (WidgetTester tester) async {
      // A PIN is seeded so the gate is real (with none set the form would
      // open directly — see the no-PIN variants below).
      await db.saveSettings(const Settings(parentPin: '1234'));
      await seedProfiles();
      await pumpPicker(tester);

      // First card autofocused.
      expect(focusedCardLabel(tester), 'profile-card-p1');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusedCardLabel(tester), 'profile-card-p2');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusedCardLabel(tester), 'add-profile-card');

      // Tap activation on the add card (pointer path).
      await tester.tap(find.byKey(addCardKey));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);
    });

    testWidgets('holding Select on a focused card opens the edit gate '
        '(D-pad long-press) without selecting the profile',
        (WidgetTester tester) async {
      await db.saveSettings(const Settings(parentPin: '1234'));
      await seedProfiles();
      await pumpPicker(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('parent-pin-prompt')), findsOneWidget);
      expect(controller.state!.activeSession, isNull,
          reason: 'a long-press is not a selection');
      // Entering the PIN leads to the edit form, never to a session start.
      for (final digit in '1234'.split('')) {
        await tester.tap(find.byKey(Key('pin-key-$digit')));
        await tester.pumpAndSettle();
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile-form')), findsOneWidget);
      expect(controller.state!.activeSession, isNull);
    });

    testWidgets('no PIN set: the add card opens the create form directly',
        (WidgetTester tester) async {
      await seedProfiles(); // no settings row: parentPin is empty
      await pumpPicker(tester);

      await tester.tap(find.byKey(addCardKey));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('parent-pin-prompt')), findsNothing);
      expect(find.byKey(const Key('profile-form')), findsOneWidget);
    });

    testWidgets('no PIN set: long-press edit opens the form directly',
        (WidgetTester tester) async {
      await seedProfiles(); // no settings row: parentPin is empty
      await pumpPicker(tester);

      await tester.longPress(find.text('Maya'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('parent-pin-prompt')), findsNothing);
      expect(find.byKey(const Key('profile-form')), findsOneWidget);
      expect(controller.state!.activeSession, isNull,
          reason: 'a long-press is not a selection');
    });

    testWidgets('a SHORT Select press still selects the profile: '
        'activation happens on key-up, well under the long-press hold',
        (WidgetTester tester) async {
      await seedProfiles();
      await pumpPicker(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('parent-pin-prompt')), findsNothing);
      expect(controller.state!.activeSession, isNotNull);
      expect(controller.state!.activeSession!.profileId, 'p1');
    });
  });
}
