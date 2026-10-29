// Shared harness for the Eleen E2E suite (integration_test on a live
// emulator).
//
// IMPORTANT: run the device suites through `tool/run_e2e.sh`, which keeps
// the SYSTEM_ALERT_WINDOW permission granted for the whole run. The home
// shows a grant banner while the permission is denied (by design), which
// shifts the layout and breaks unrelated assertions on a plain
// `flutter test` run; integration_test also uninstalls the app at the end,
// dropping a one-shot grant.
//
// Design (single-device E2E):
//
// - Every scenario pumps the production `EleenApp` directly with an explicit
//   [FormFactor] — the existing test seam in main.dart — so no form-factor
//   override inside main() is needed. The `ELEEN_FORM` dart-define
//   (tv|phone|all, default all) only gates which scenario groups run.
// - TV scenarios (1, 5, 6) run the production bootstrap path: the profile is
//   seeded straight into the file-backed Drift database that
//   `TvController.forDevice()` opens (`getApplicationDocumentsDirectory() /
//   eleen.sqlite3`), then `EleenApp(formFactor: tv)` builds its own
//   controller + LAN server exactly like a real launch.
// - Phone scenarios (2, 3, 4) run against a headless in-process `EleenServer`
//   started by the test on the device's loopback (port 0 -> ephemeral), with
//   the phone UI paired through the scanner screen's manual-address fallback
//   by pasting the full `eleen://pair?host=127.0.0.1&port=..&nonce=..`
//   payload. The test generates the nonce and registers it with the server
//   exactly like `PairingScreen` does via `TvController.registerPairingNonce`.
//   The server's coordinator is backed by its own file (not the TV's), so
//   scenario 4 can open a second connection to the same file and render the
//   production TV home over the same server state.
// - Real overlay (SYSTEM_ALERT_WINDOW) rendering and real camera scanning are
//   deliberately out of scope (real-device checklist); the scanner screen
//   still loads on the emulator and degrades to its manual-code field.
// - Speed: `--dart-define=ELEN_FAST=1` sets speedFactor 60 (see
//   `TvController.defaultSpeedFactor`), so a 15-minute allowance expires in
//   ~15 wall seconds.

import 'dart:io';

import 'package:drift/drift.dart' show LazyDatabase;
import 'package:drift/native.dart';
import 'package:eleen/state/tv_controller.dart';
import 'package:eleen_core/eleen_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:eleen/form_factor.dart' show FormFactor;
export 'package:eleen/main.dart' show EleenApp;

/// The scenario filter: 'tv' runs only the TV scenarios, 'phone' only the
/// phone ones, anything else (unset) runs all six.
const String _formFilter = String.fromEnvironment('ELEEN_FORM');

final bool runTvScenarios = _formFilter != 'phone';

final bool runPhoneScenarios = _formFilter != 'tv';

/// The parent PIN seeded into every test database. PINs are exactly 4
/// digits (BUG-4/7), so the seed is 4 digits too.
const String e2eParentPin = '1234';

/// A bearer token seeded into the TV database when a scenario needs to
/// dial the TV's production LAN server as a paired client would (the TV
/// scenarios never pair, so the settings token would otherwise be null).
const String e2ePairToken = 'e2e-usage-token';

/// The test child profile: a 15-minute allowance so speedFactor 60 expires it
/// in ~15 wall seconds and the 10/5-minute reminder thresholds are both
/// reachable (they only fire below the session start of 15 minutes).
Profile e2eProfile(String id) => Profile(
      id: id,
      name: 'Maya',
      avatar: 'M',
      allowance: AllowanceMinutes.fifteen,
    );

/// The test parent profile: never expires; selecting it on the picker
/// demands the parent PIN.
Profile e2eParentProfile(String id) => Profile(
      id: id,
      name: 'Ava',
      avatar: 'A',
      allowance: AllowanceMinutes.thirty,
      isParent: true,
    );

/// Integration-test binding; call before anything else in `main()`.
void ensureE2eBinding() => IntegrationTestWidgetsFlutterBinding.ensureInitialized();

/// Wall-clock pump loop: integration tests run real async (LiveTestWidgets-
/// FlutterBinding), so real timers (the 1s tick loop, the 5s toast timer)
/// fire while [Future.delayed] awaits; the interleaved [pump]s flush frames.
Future<void> pumpFor(WidgetTester tester, Duration wall) async {
  final end = DateTime.now().add(wall);
  while (DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
}

/// Polls until [finder] finds at least one widget, pumping frames while the
/// wall clock runs. Fails with a timeout message after [timeout].
Future<void> waitForFound(
  WidgetTester tester,
  Finder finder,
  Duration timeout, {
  String? context,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  await tester.pump();
  fail('Timed out after $timeout waiting for $finder'
      '${context == null ? '' : ' ($context)'}');
}

/// Polls until [finder] finds nothing, pumping frames while the wall clock
/// runs.
Future<void> waitForGone(
  WidgetTester tester,
  Finder finder,
  Duration timeout,
) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump();
    if (finder.evaluate().isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  fail('Timed out after $timeout waiting for $finder to disappear');
}

/// The m:ss remaining-time text on the TV home status row (and the
/// last-minute badge, same format — the highest value wins, which is the
/// main readout).
Finder get countdownTextFinder => find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          RegExp(r'^\d+:\d{2}$').hasMatch(widget.data!),
    );

/// The remaining session seconds currently on the TV home status row, or
/// null while no session is enforced.
int? remainingFromUi(WidgetTester tester) {
  int? best;
  for (final widget in countdownTextFinder.evaluate()) {
    final text = (widget.widget as Text).data!;
    final parts = text.split(':');
    final value = int.parse(parts[0]) * 60 + int.parse(parts[1]);
    if (best == null || value > best) best = value;
  }
  return best;
}

/// Deletes [fileName] (plus its WAL/SHM sidecars) from the app documents
/// directory, retrying briefly in case a previous test's controller is still
/// closing its connection.
Future<void> deleteDbFile(String fileName) async {
  final dir = await getApplicationDocumentsDirectory();
  final base = File(p.join(dir.path, fileName));
  for (final file in [
    base,
    File('${base.path}-wal'),
    File('${base.path}-shm'),
  ]) {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (!await file.exists()) break;
      try {
        await file.delete();
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }
}

/// Seeds the production TV database (the exact file `TvController.forDevice()`
/// opens) with one profile and the parent PIN, then closes the connection so
/// the app can open it fresh. With [includeParentProfile] a parent profile
/// (`e2e-parent`) is seeded too.
Future<void> seedDeviceTvDb({
  required String parentPin,
  bool includeParentProfile = false,
  String? token,
  List<Profile> extraProfiles = const [],
}) async {
  await deleteDbFile('eleen.sqlite3');
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'eleen.sqlite3'));
  final db = EleenDatabase(
      LazyDatabase(() async => NativeDatabase(file)));
  await db.upsertProfile(e2eProfile('e2e-kid'));
  if (includeParentProfile) {
    await db.upsertProfile(e2eParentProfile('e2e-parent'));
  }
  for (final profile in extraProfiles) {
    await db.upsertProfile(profile);
  }
  await db.saveSettings(Settings(parentPin: parentPin, token: token));
  await db.close();
}

/// Polls [client] until the TV server answers (the production server may
/// still be binding right after a relaunch), returning the first state.
Future<TvState> stateWithRetry(EleenClient client,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      return await client.state();
    } on EleenOffline {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
}

/// Unmounts whatever is on screen and disposes any controllers owned by the
/// app (TvHome closes its controller's db on dispose).
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// A second connection to the device TV db (the exact file the production
/// `TvController.forDevice()` opens), for asserting the state the phone
/// would see through the server — the same source of truth, read directly.
Future<EleenDatabase> openDeviceTvDb() async {
  final dir = await getApplicationDocumentsDirectory();
  return EleenDatabase(
      LazyDatabase(() async => NativeDatabase(File(p.join(dir.path,
          'eleen.sqlite3')))));
}

/// A headless TV for the phone scenarios: a real [EleenServer] over a
/// file-backed [EleenDatabase] on the device's loopback, driven by the test
/// instead of the TV UI.
class PhoneTestTv {
  PhoneTestTv();

  late final EleenDatabase db;
  late final EngineCoordinator coordinator;
  late final EleenServer server;

  /// The file backing [db] — scenario 4 opens a second connection to render
  /// the production TV home over the same state.
  late File dbFile;

  Future<void> start() async {
    await deleteDbFile('eleen-e2e-phone.sqlite3');
    final dir = await getApplicationDocumentsDirectory();
    dbFile = File(p.join(dir.path, 'eleen-e2e-phone.sqlite3'));
    db = EleenDatabase(LazyDatabase(() async => NativeDatabase(dbFile)));
    coordinator = EngineCoordinator(
      db: db,
      engine: TimeEngine(
        clock: SystemClock(),
        speedFactor: TvController.defaultSpeedFactor,
      ),
    );
    server = EleenServer(coordinator: coordinator);
    await server.start(address: InternetAddress.loopbackIPv4, port: 0);
  }

  /// Seeds the parent PIN and the test child profile.
  Future<void> seed({required String parentPin}) async {
    await db.saveSettings(Settings(parentPin: parentPin));
    await db.upsertProfile(e2eProfile('e2e-kid'));
  }

  /// Seeds an active session for the test profile with [remainingSeconds]
  /// (scenario 4 needs a live session so "remaining preserved" is
  /// meaningful).
  Future<void> seedActiveSession({required int remainingSeconds}) async {
    await db.saveSession(SessionState(
      profileId: 'e2e-kid',
      date: coordinator.engine.clock.today(),
      remainingSeconds: remainingSeconds,
      active: true,
    ));
  }

  /// Registers a fresh single-use nonce (as the TV pairing screen does) and
  /// returns the full payload to paste into the scanner's manual field.
  String newPairingPayload() {
    final nonce = PairingCodec.newNonce();
    server.registerNonce(nonce);
    return PairingCodec.payload(
      host: '127.0.0.1',
      port: server.port,
      nonce: nonce,
    );
  }

  Future<void> stop() async {
    await server.stop();
    await db.close();
  }
}

/// Wipes the phone app's persisted pairing so every phone scenario starts
/// unpaired (shared_preferences is real in integration tests and would
/// otherwise leak pairing between scenarios/runs).
Future<void> clearPhonePairing() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

/// Pairs the phone UI with the test TV via the scanner screen's
/// manual-address fallback: opens the scanner, pastes the full
/// `eleen://pair?...` payload, submits, and waits for the paired home.
Future<void> pairViaManualCode(WidgetTester tester, PhoneTestTv tv) async {
  // PhoneHome resolves the paired store asynchronously; wait for the
  // unpaired home to render before opening the scanner.
  await waitForFound(
    tester,
    find.text('Scan TV code'),
    const Duration(seconds: 30),
    context: 'unpaired phone home',
  );
  await tester.tap(find.text('Scan TV code'));
  await waitForFound(tester, find.byKey(const Key('manual-payload')),
      const Duration(seconds: 30),
      context: 'scanner manual field');
  await tester.enterText(
      find.byKey(const Key('manual-payload')), tv.newPairingPayload());
  await tester.pump();
  await tester.tap(find.byKey(const Key('manual-submit')));
  await waitForFound(
    tester,
    find.textContaining('Paired to 127.0.0.1'),
    const Duration(seconds: 30),
    context: 'paired home after manual pairing',
  );
  // The success snackbar sits over the centered buttons on this screen and
  // swallows the next tap; wait for it to time out first.
  await waitForGone(
    tester,
    find.byType(SnackBar),
    const Duration(seconds: 15),
  );
}

/// Opens the profiles dashboard and waits for the test profile's row.
Future<void> openDashboard(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('open-dashboard')));
  await waitForFound(tester, find.byKey(const Key('profile-row-e2e-kid')),
      const Duration(seconds: 30),
      context: 'dashboard rows after pairing');
}

/// Runs the PIN dialog for the pending phone action ([PinDialog.show] or
/// [PinDialog.run] variants alike use the same keys).
Future<void> submitPin(WidgetTester tester, String pin) async {
  await waitForFound(tester, find.byKey(const Key('pin-field')),
      const Duration(seconds: 15),
      context: 'PIN dialog');
  await tester.enterText(find.byKey(const Key('pin-field')), pin);
  await tester.pump();
  await tester.tap(find.byKey(const Key('pin-submit')));
}

/// Types [pin] on the on-screen TV PIN pad (the pad used by the picker's
/// management gate and the lock overlay).
Future<void> tapTvPin(WidgetTester tester, String pin) async {
  for (final digit in pin.split('')) {
    await tester.tap(find.byKey(Key('pin-key-$digit')));
    await pumpFor(tester, const Duration(milliseconds: 120));
  }
}

/// Drives one full TV enforcement start: taps the "Enforce time" toggle for
/// [profileId] on the picker, clears the parent-PIN gate when one appears,
/// and waits for the home status row to show the live remaining time. The
/// home is the only main screen now — there is no countdown screen.
///
/// The toggle is gated only when a parent PIN is set, so this tolerates both
/// shapes: a prompt (cleared with [pin]) or a direct start.
Future<void> selectProfileOnTv(
  WidgetTester tester, {
  String profileId = 'e2e-kid',
  String pin = e2eParentPin,
}) async {
  await tester.tap(find.byKey(Key('profile-toggle-$profileId')));
  // Wait for whichever comes first: the PIN gate or the started session.
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  var gated = false;
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump();
    if (find.byKey(const Key('parent-pin-prompt')).evaluate().isNotEmpty) {
      gated = true;
      break;
    }
    if (find.byKey(const Key('enforced-remaining')).evaluate().isNotEmpty) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  if (gated) {
    await tapTvPin(tester, pin);
  }
  await waitForFound(
    tester,
    find.byKey(const Key('enforced-remaining')),
    const Duration(seconds: 30),
    context: 'home status row after enabling enforcement',
  );
}
