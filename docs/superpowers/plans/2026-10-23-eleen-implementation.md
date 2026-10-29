# Eleen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Eleen — a single Flutter app (Android TV + phone, adaptive UI) that enforces per-profile daily TV time budgets, syncs TV↔phone over local Wi-Fi via TV-hosted HTTP + QR pairing.

**Architecture:** `packages/core` is a pure-Dart package (models, time engine, Drift storage, HTTP server/client, pairing) — fully unit-testable without Flutter. `app/` is one Flutter app that detects form factor at startup: TV UI (picker, countdown, toasts, overlay, QR pairing) vs phone UI (scanner, profile list, overrides, master lock). TV instance is the source of truth; phone talks REST over LAN.

**Tech Stack:** Flutter 3.47 / Dart 3, Drift (SQLite), `qr_flutter` (TV QR display), `mobile_scanner` (phone scan), `flutter_overlay_window` (always-on-top lock), `bonsoir` (mDNS fallback), `integration_test` (E2E).

**Spec:** `docs/superpowers/specs/2026-10-23-tv-time-guard-design.md`

## Global Constraints

- App name/copy everywhere: **Eleen**.
- One app, one APK/AAB — `LEANBACK_LAUNCHER` intent so it launches from TV home; no separate TV/phone builds.
- LAN-only sync: HTTP over Wi-Fi, no internet calls anywhere in the code.
- No dependency on other apps; scanning is in-app (`mobile_scanner`), camera permission only.
- Allowances restricted to 15 / 30 / 45 / 60 minutes (enum, not int).
- Timer uses monotonic elapsed time (`Stopwatch`-style), never wall clock.
- Reminder thresholds: toasts at remaining 15 / 10 / 5 min, only thresholds strictly below session start; each fires once per session; adding time re-arms lower thresholds.
- Last 60 seconds: per-second countdown pinned top-right.
- Master lock blocks all profiles; lifted lock restores preserved remaining times.
- QR pairing nonce is single-use; old codes must fail.
- TV UI is proportional/responsive (`MediaQuery`/`LayoutBuilder`), fills any resolution 720p–4K; no fixed pixel sizes for layout.
- E2E runs fast: a debug flag scales all durations by 1/60.
- All state changes (add/override/lock/profile edits) require shared token + parent PIN.
- Secrets never committed: `key.properties`, keystores gitignored.
- Every task: tests fail first, pass after, then commit.

---

### Task 1: Workspace scaffold + core package

**Files:**
- Create: `packages/core/pubspec.yaml`, `packages/core/lib/eleen_core.dart`, `packages/core/test/smoke_test.dart`
- Create: `.gitignore` additions (`.dart_tool/`, `build/`, `key.properties`, `*.jks`)

**Interfaces:**
- Produces: Dart package `eleen_core` (name in pubspec) importable as `package:eleen_core/eleen_core.dart`.

- [ ] **Step 1: Create the package**

```bash
cd /Users/mnawaz/Netskope/tv_guard
mkdir -p packages/core
cat > packages/core/pubspec.yaml <<'EOF'
name: eleen_core
description: Eleen core - models, time engine, storage, LAN sync API.
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.9.0
dependencies:
  drift: ^2.28.0
  sqlite3_flutter_libs: ^0.5.32
  meta: ^1.17.0
dev_dependencies:
  test: ^1.26.0
  drift_dev: ^2.28.0
  build_runner: ^2.7.0
EOF
cat > packages/core/lib/eleen_core.dart <<'EOF'
/// Eleen core library.
library eleen_core;
EOF
cat > packages/core/test/smoke_test.dart <<'EOF'
import 'package:test/test.dart';
import 'package:eleen_core/eleen_core.dart';

void main() {
  test('package imports', () {}, skip: false);
}
EOF
cd packages/core && dart pub get
```

- [ ] **Step 2: Run test**

Run: `cd packages/core && dart test`
Expected: 1 PASS.

- [ ] **Step 3: Commit**

```bash
git add packages .gitignore && git commit -m "chore: scaffold eleen_core package"
```

---

### Task 2: Domain models

**Files:**
- Create: `packages/core/lib/src/models.dart` → export from `eleen_core.dart`
- Test: `packages/core/test/models_test.dart`

**Interfaces:**
- Produces:
  - `enum AllowanceMinutes { fifteen, thirty, fortyFive, sixty }` with `int get minutes` (15/30/45/60) and `static AllowanceMinutes? fromMinutes(int m)`
  - `class Profile { final String id; final String name; final String avatar; final AllowanceMinutes allowance; }`
  - `class SessionState { final String profileId; final DateTime date; final int remainingSeconds; final bool active; }`
  - `class TvState { final List<Profile> profiles; final SessionState? activeSession; final bool masterLockEnabled; final Map<String,int> remainingByProfile; }`
  - `class Settings { final String parentPin; final String? token; final bool masterLockEnabled; }`

- [ ] **Step 1: Write failing tests** — `fromMinutes(30) == AllowanceMinutes.thirty`, `fromMinutes(20) == null` (20-min example from spec is invalid as an allowance), each enum `.minutes` value, `TvState` default `masterLockEnabled == false`.
- [ ] **Step 2:** `dart test` → FAIL (models not defined).
- [ ] **Step 3:** Implement `models.dart`, add `export 'src/models.dart';` to `eleen_core.dart`.
- [ ] **Step 4:** `dart test` → PASS. **Step 5:** commit `feat(core): domain models`.

---

### Task 3: Time engine

**Files:**
- Create: `packages/core/lib/src/time_engine.dart` → export from `eleen_core.dart`
- Test: `packages/core/test/time_engine_test.dart`

**Interfaces:**
- Consumes: models from Task 2.
- Produces:
  - `abstract class Clock { int nowMs(); }` (monotonic; `SystemClock` impl uses `Stopwatch`)
  - `class TimeEngine`
    - `TimeEngine({required Clock clock, int speedFactor = 1})` (speedFactor 60 = 1/60 durations for E2E)
    - `List<int> firedThresholds` / behavior: `tick(int elapsedMs)` style pure reducer — recommended shape:
    - `SessionState advance(SessionState s, int deltaMs, AllowanceMinutes allowance)` — subtracts `deltaMs * speedFactor`, floors at 0, rolls `date` (daily reset returns full allowance when date != today)
    - `int? thresholdToFire(int remainingSecBefore, int remainingSecAfter, int sessionStartSec)` — returns 15/10/5-minute (in seconds, scaled by speedFactor) threshold crossed, only if `thresholdSec < sessionStartSec`; null otherwise
    - `bool get inLastMinute(int remainingSec)` → `remainingSec <= 60 * speedFactor && remainingSec > 0`
    - master lock: `SessionState applyMasterLock(SessionState s, {required bool locked, AllowanceMinutes allowance})` — locked true keeps remaining (preserved), marks inactive; false restores.
  - Single-fire/re-arm rule lives here: engine returns threshold once; caller records fired set per session; `addTime` clears the set of thresholds below new remaining.

- [ ] **Step 1: Failing tests** (write these exact cases):
  - advance subtracts elapsed; floors at 0.
  - date rollover resets remaining to allowance.
  - threshold fires at 10-min crossing when start was 15 min; 15-min threshold does NOT fire when start was 15 min (equal to start).
  - 30-min start fires 15, 10, 5; each fires once (second crossing of same value returns null).
  - last-minute window `inLastMinute`.
  - master lock preserves remaining, unlock restores.
  - speedFactor=60: a 15-min allowance expires after 15 "minutes" of scaled time in 15 wall-seconds.
- [ ] **Step 2:** verify FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(core): time engine with thresholds, daily reset, master lock`.

---

### Task 4: Drift storage

**Files:**
- Create: `packages/core/lib/src/db.dart` (Drift database + DAOs) → export from `eleen_core.dart`
- Create: `packages/core/lib/src/db.g.dart` (generated — run build_runner)
- Test: `packages/core/test/db_test.dart` (use `NativeDatabase.memory()`)

**Interfaces:**
- Produces: `class EleenDatabase extends _$EleenDatabase` with tables `Profiles`, `Sessions`, `AppSettings` (single row: parentPin, token, masterLockEnabled), and methods:
  - `Future<List<Profile>> allProfiles()`, `Future<void> upsertProfile(Profile p)`, `Future<void> deleteProfile(String id)`
  - `Future<SessionState?> sessionFor(DateTime date)`, `Future<void> saveSession(SessionState s)`
  - `Future<Settings> getSettings()`, `Future<void> saveSettings(Settings s)`

- [ ] **Step 1: Failing tests** — upsert/read profile round-trip; save/get session persists remaining seconds; settings round-trip incl. masterLockEnabled.
- [ ] **Step 2:** FAIL. **Step 3:** implement + `dart run build_runner build` (commit the generated file). **Step 4:** PASS. **Step 5:** commit `feat(core): drift persistence`.

---

### Task 5: HTTP API server + auth

**Files:**
- Create: `packages/core/lib/src/server.dart` → export from `eleen_core.dart`
- Test: `packages/core/test/server_test.dart`

**Interfaces:**
- Consumes: `EleenDatabase`, `TimeEngine`, models.
- Produces: `class EleenServer { Future<void> start({required InternetAddress address, int port = 8477}); Future<void> stop(); }` wired to a `class EngineCoordinator` (same file) that owns engine+db and exposes the operations below. JSON contract (exact field names — phone client (Task 8) and E2E use these):
  - `POST /api/pair {nonce}` → `{token}` (nonce single-use; wrong/old nonce → 401). Nonces generated by TV pairing screen (Task 10) via `PairingCodec.newNonce()`.
  - `GET /api/state` → `{"profiles":[{id,name,avatar,allowanceMinutes}], "activeProfileId": String?, "remainingByProfile": {id: seconds}, "masterLockEnabled": bool}`
  - `POST /api/profiles {name, avatar, allowanceMinutes, pin}` / `PATCH /api/profiles/{id} {..., pin}` (pin = parent PIN, verified server-side)
  - `POST /api/time {profileId, addSeconds, pin}` → remaining after add; re-arms thresholds (clears fired set entries below new remaining)
  - `PUT /api/time/{profileId} {remainingSeconds, pin}` → override
  - `POST /api/lock {enabled, pin}`
  - All except `/api/pair` require header `Authorization: Bearer <token>` else 401.
  - Also create `class PairingCodec { static String payload({required String host, required int port, required String nonce})` → `eleen://pair?host=..&port=..&nonce=..`; `static ({String host,int port,String nonce})? parse(String payload)`.

- [ ] **Step 1: Failing tests** — pair issues token; reused nonce → 401; state JSON shape as above; add/override/lock rejected without token and with wrong PIN; add-time result math.
- [ ] **Step 2:** FAIL. **Step 3:** implement (`HttpServer.bind` on `InternetAddress.anyIPv4`; JSON via `jsonEncode`). **Step 4:** PASS (tests use real sockets on `127.0.0.1`, ephemeral port). **Step 5:** commit `feat(core): LAN HTTP server with token+PIN auth`.

---

### Task 6: Phone-side API client

**Files:**
- Create: `packages/core/lib/src/client.dart` → export from `eleen_core.dart`
- Test: `packages/core/test/client_test.dart`

**Interfaces:**
- Consumes: `EleenServer` (tests start it in-process on loopback), `PairingCodec`.
- Produces: `class EleenClient { EleenClient({required Uri base, String? token}); Future<String> pair(String nonce); Future<TvState> state(); Future<void> addTime(String profileId,int addSeconds,String pin); Future<void> overrideTime(String profileId,int remainingSeconds,String pin); Future<void> setMasterLock(bool enabled,String pin); Future<void> upsertProfile(Profile p,String pin); }` — throws `EleenOffline` on `SocketException` (drives the phone "TV offline" UI).

- [ ] **Step 1: Failing tests** — pair → token stored; state parses to `TvState`; offline path: stop server → `state()` throws `EleenOffline`; PIN errors surface as `EleenApiError(status)`.
- [ ] **Step 2:** FAIL. **Step 3:** implement with `HttpClient`. **Step 4:** PASS. **Step 5:** commit `feat(core): phone API client`.

---

### Task 7: Flutter app scaffold + form-factor detection + AndroidManifest

**Files:**
- Create: `app/` via `flutter create --org com.eleen --project-name eleen app`
- Modify: `app/android/app/src/main/AndroidManifest.xml`
- Create: `app/lib/main.dart`, `app/lib/form_factor.dart`
- Modify: `app/pubspec.yaml` (add `eleen_core` path dep, `qr_flutter`, `mobile_scanner`, `flutter_overlay_window`, `bonsoir`, `device_info_plus`)

**Interfaces:**
- Produces: `enum FormFactor { tv, phone }`; `Future<FormFactor> detectFormFactor()` (device_info_plus: `systemFeatures` contains `android.hardware.type.television` or `leanback` flag → tv). `main.dart` runs `MaterialApp(home: switch on formFactor → TvHome | PhoneHome)`.

- [ ] **Step 1:** scaffold app, add deps, `flutter pub get`.
- [ ] **Step 2: Manifest** — in `<manifest>` add:
  - `<uses-feature android:name="android.software.leanback" android:required="false"/>` and `<uses-feature android:name="android.hardware.touchscreen" android:required="false"/>`
  - permissions: `INTERNET`, `CAMERA`, `SYSTEM_ALERT_WINDOW` (overlay), `ACCESS_NETWORK_STATE`
  - in `<application>`: `android:banner="@drawable/tv_banner"` (add placeholder 320×180 PNG at `app/android/app/src/main/res/drawable/tv_banner.png`), and add a second `<intent-filter>` with `LEANBACK_LAUNCHER` + `CATEGORY_LEANBACK_LAUNCHER`.
- [ ] **Step 3:** implement `form_factor.dart` + minimal `main.dart` with placeholder `TvHome`/`PhoneHome` widgets showing "Eleen TV"/"Eleen Phone".
- [ ] **Step 4:** `cd app && flutter analyze && flutter test` → clean. Boot check on both AVDs: `flutter run -d eleen_tv` (shows TV label, launches), same for `eleen_phone`.
- [ ] **Step 5:** commit `feat(app): Eleen scaffold, leanback manifest, form-factor detection`.

---

### Task 8: TV home + profile picker

**Files:**
- Create: `app/lib/tv/tv_home.dart`, `app/lib/tv/profile_picker.dart`
- Create: `app/lib/state/tv_controller.dart` (ChangeNotifier wrapping `EleenDatabase` + `TimeEngine` + `EleenServer`; starts server on the device's LAN IP)

**Interfaces:**
- Consumes: core models/db/server/engine (Tasks 2–6).
- Produces: `TvController` with `List<Profile> get profiles`, `Future<void> selectProfile(String id)` (creates/resumes today's session), `Stream<TvState> get stateStream`. Profile picker: responsive `GridView` (avatars + names, D-pad focusable, `LayoutBuilder`-proportional cells).

- [ ] **Step 1: Failing widget test** — picker renders profiles from a seeded `TvController` (in-memory db); D-pad selection calls `selectProfile`; grid fills available size (no fixed pixel cell sizes).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS + `flutter analyze` clean. **Step 5:** commit `feat(tv): profile picker`.

---

### Task 9: TV countdown screen — timer, toasts, last-minute countdown

**Files:**
- Create: `app/lib/tv/countdown_screen.dart`, `app/lib/tv/widgets/reminder_toast.dart`, `app/lib/tv/widgets/last_minute_countdown.dart`
- Modify: `app/lib/state/tv_controller.dart` (tick loop, fired-threshold set, re-arm on addTime)

**Interfaces:**
- Consumes: `TimeEngine.advance/thresholdToFire/inLastMinute` (Task 3), speedFactor from `bool kDebugTimeScale` (dart-define `ELEN_FAST=1` → speedFactor 60).
- Produces: countdown screen shows remaining `mm:ss` centered, scaled by `MediaQuery`; `ReminderToast("10 minutes left")` — `SnackBar`-style overlay shown 5s, once per threshold; `LastMinuteCountdown` — `Positioned` top-right in a `Stack`, ticks per second, responsive font (`MediaQuery.textScalerOf`), disappears when overlay takes over.

- [ ] **Step 1: Failing widget tests** — controller with speedFactor 60: 15-min session; toast events observed at 10 and 5 scaled-minute marks, exactly once each; `LastMinuteCountdown` visible only in last scaled-minute; countdown text format `m:ss`.
- [ ] **Step 2:** FAIL. **Step 3:** implement (`Timer.periodic(1s)` driving `TvController.tick`). **Step 4:** PASS. **Step 5:** commit `feat(tv): countdown, reminder toasts, last-minute widget`.

---

### Task 10: TV lock overlay + PIN pad

**Files:**
- Create: `app/lib/tv/lock_overlay.dart`, `app/lib/tv/widgets/pin_pad.dart` (D-pad grid 0–9)
- Modify: `app/lib/tv/tv_home.dart` (when remaining==0 or masterLock: show overlay)

**Interfaces:**
- Consumes: `TvController` (state, PIN check against `Settings.parentPin`, addTime after PIN).
- Produces: full-screen `LockOverlay(message: "Time's up!", onUnlock: (addMinutes) {...})`; uses `flutter_overlay_window` (`OverlayType.default`, full-screen flag) when app is in background so the lock still covers the TV; in-app equivalent widget when app is foregrounded (same UI, so widget tests don't need platform overlay). PIN pad: `Focus`-traversable grid, correct PIN → "Add 15 / 30 min" chooser → overlay clears. Master lock shows same overlay with "Locked by parent" copy, no PIN exit (unlock only from phone).

- [ ] **Step 1: Failing widget tests** — overlay covers `MediaQuery` full size; PIN pad D-pad traversal order 1→9,0; wrong PIN shows error, stays; correct PIN + 15-min → `onUnlock(15)` called; master-lock variant exposes no unlock affordance.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(tv): time-up lock overlay with D-pad PIN pad`.

---

### Task 11: TV pairing screen (QR)

**Files:**
- Create: `app/lib/tv/pairing_screen.dart`

**Interfaces:**
- Consumes: `PairingCodec.payload` (Task 5), `TvController.currentPairingNonce` (generated on open, single-use, regenerates after pair).
- Produces: responsive centered `QrImageView(data: payload, size: MediaQuery...shortestSide * 0.5)`; shows "Pairing complete ✓" on success; screen reachable from TV home settings row. Also register mDNS via `bonsoir`: service `_eleen._tcp`, port 8477, name "Eleen-TV".

- [ ] **Step 1: Failing widget test** — QR rendered with `eleen://pair?host=...&nonce=...` payload; new nonce each open.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(tv): QR pairing screen + mDNS registration`.

---

### Task 12: Phone pairing flow (scanner + fallback)

**Files:**
- Create: `app/lib/phone/phone_home.dart`, `app/lib/phone/pairing/scanner_screen.dart`, `app/lib/phone/pairing/paired_store.dart` (shared_preferences for token + tv host)

**Interfaces:**
- Consumes: `mobile_scanner` (`MobileScannerController`), `EleenClient.pair` (Task 6), `PairingCodec.parse`, `bonsoir` discovery fallback.
- Produces: `ScannerScreen` with live camera preview, in-app only; on `eleen://pair` detection → `client.pair(nonce)` → store token → navigate to profiles; manual "enter TV address" field as discovery fallback when camera unavailable/mDNS blocked.

- [ ] **Step 1: Failing widget tests** — payload parse routes to pair call with extracted host/port/nonce (mock scanner payload); bad payload shows error; successful pair persists token (mock `PairedStore`).
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(phone): QR scanner pairing with address fallback`.

---

### Task 13: Phone profiles dashboard — list, add/override, master lock

**Files:**
- Create: `app/lib/phone/profiles_screen.dart`, `app/lib/phone/widgets/pin_dialog.dart`, `app/lib/phone/widgets/master_lock_switch.dart`
- Create: `app/lib/state/phone_controller.dart` (ChangeNotifier: polls `client.state()` every 5s; exposes `TvState?`, `EleenOffline` → `offline` flag)

**Interfaces:**
- Consumes: `EleenClient` ops (Task 6).
- Produces: profile list rows: avatar, name, allowance chip, live remaining `mm:ss` (from poll); per-row actions: "Add time" (PIN dialog → `addTime` 15/30/45/60), "Override" (PIN dialog → minute-picker → `overrideTime`); allowance editor on row long-press (PIN); `MasterLockSwitch` (PIN confirm → `setMasterLock`); offline banner "TV offline — check both devices are on the same Wi-Fi" when `offline`.

- [ ] **Step 1: Failing widget tests** — rows render from mock `TvState` with live remaining; Add-time flow with PIN calls controller (mock); override flow; master lock toggle requires PIN; offline state shows banner.
- [ ] **Step 2:** FAIL. **Step 3:** implement. **Step 4:** PASS. **Step 5:** commit `feat(phone): profiles dashboard with overrides and master lock`.

---

### Task 14: End-to-end integration tests

**Files:**
- Create: `app/integration_test/e2e_test.dart`, `app/integration_test/helpers/tv_harness.dart`

**Interfaces:**
- Consumes: everything; uses `--dart-define=ELEN_FAST=1` (speedFactor 60; 15-min allowance expires in ~15s; toasts at 10/5 scaled minutes fire in 10s/5s).

- [ ] **Step 1: Write the six scenarios as `integration_test`** (TV ones on `eleen_tv` AVD; pairing scenarios run app twice / or split: scenario 1,5,6 on TV AVD; 2,3,4 need two instances — implement by running the phone-side flows against a headless in-process `EleenServer` started by the test on the host loopback, with the phone UI pointed at it via the manual-address fallback — this keeps E2E single-device and CI-runnable):
  1. TV: create profile (15 min) via seed → picker → session runs → expire → overlay → PIN add 15 → overlay clears.
  2. Phone: pair via manual-address with test nonce → profile list shows remaining → addTime → server state increased.
  3. Phone: override remaining → state reflects.
  4. Phone: master lock on → state.masterLockEnabled, TV overlay shown; lock off → remaining preserved.
  5. TV: relaunch (restart app) mid-session → remaining persisted and resumed.
  6. TV: toasts observed at scaled 10/5; last-minute countdown visible in final scaled minute.
- [ ] **Step 2: Run** `cd app && flutter test integration_test --dart-define=ELEN_FAST=1 -d eleen_tv` → all pass.
- [ ] **Step 3:** Commit `test: E2E scenarios 1-6`.

---

### Task 15: Release build + signing + store readiness

**Files:**
- Modify: `app/android/app/build.gradle(.kts)` (signingConfigs from `key.properties`)
- Create: `docs/release.md` (runbook steps 5–6 concretely), `app/android/key.properties.example`
- Modify: `.gitignore` (`key.properties`, `*.jks`, `*.keystore`)

- [ ] **Step 1:** Add release signing config reading `key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); example file committed, real one gitignored.
- [ ] **Step 2:** `flutter build appbundle --release` succeeds (with a locally-generated test keystore; document `keytool -genkeypair -v -keystore eleen-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`).
- [ ] **Step 3:** `docs/release.md` = store listing checklist (data safety: no data collected; TV banner 320×180 at `res/drawable/tv_banner.png`; screenshots; content rating; internal-track → real-device verify → promote).
- [ ] **Step 4:** Commit `build: release signing and store checklist`.

---

## Self-Review (done)

- Spec coverage: reqs 1–10 map to Tasks 7 (install/adaptive), 2/4 (profiles), 2 (allowance enum), 9–10 (overlay/task 10 + 9), 5 (PIN adds — tasks 5,10,13), 6–8 (phone mgmt, override, master lock — tasks 5,6,13), 9 (toasts — task 3 engine + 9 UI), 10 (countdown widget — task 9), QR (tasks 5,11,12), responsive TV UI (constraint + tasks 8–11), E2E (task 14), Play (task 15), no-internet/no-app-dependency (constraint + task 12).
- No placeholders; each task names files, signatures, and test cases.
- Type consistency checked (`AllowanceMinutes`, `TimeEngine`, `EleenServer/Client`, `TvController/PhoneController` names used consistently).
