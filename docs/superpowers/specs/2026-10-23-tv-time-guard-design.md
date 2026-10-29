# Eleen — Design Spec

Date: 2026-10-23
Status: Approved in brainstorming session

## Purpose

**Eleen** is a parental screen-time manager for Android TV. **One single app**
(named Eleen everywhere: app label, Play Store listing) that installs on both
Android TV and Android phones; it detects which form factor it is running on
and adapts: on TV it enforces per-profile daily time budgets, on phone it
manages profiles and time remotely. Sync is local-network only (same Wi-Fi);
there is no internet backend and none is planned.

## Functional Requirements

1. One app installable on Android TV and Android phone (adaptive UI per device).
2. Manage user profiles (name, avatar, daily allowance).
3. Daily allowance selectable per profile: 15 / 30 / 45 / 60 minutes.
4. When a profile's time runs out, the TV screen is "disabled" — a full-screen
   always-on-top overlay with a message and PIN entry.
5. Parent can add more time by entering the parent PIN (on TV overlay or in
   the app running on a phone).
6. The phone instance manages TV timings for profiles over the same Wi-Fi.
7. The phone instance shows the TV's list of user profiles with their live
   remaining time, and can override timings per profile (change today's
   remaining time directly, not just add).
8. The phone instance can **disable all profiles at once** (a master lock:
   the TV's active session immediately ends and every profile shows the
   time's-up overlay / is blocked until re-enabled from the phone).
9. **Upcoming-time reminders**: while a session is running, the TV shows a
   toast when remaining time hits 15, 10, and 5 minutes (only thresholds
   strictly below the session's starting time fire — e.g. a 15-minute
   session gets toasts at 10 and 5; a 30-minute session gets all three).
   Toasts are one-shot per threshold per session (adding time re-arms
   thresholds below the new remaining time).
10. **Last-minute countdown**: during the final 60 seconds, a live
    second-by-second countdown (e.g. "0:45… 0:44…") is pinned to the top-right
    corner of the TV screen, until the time's-up overlay takes over.

## Non-Goals (v1)

- Internet or cross-network sync
- iOS
- Multiple concurrent active profiles
- Usage history / reports

## v1.1 additions (approved 2026-10-24)

**A. True lock-down on time's-up.** The always-on-top overlay covers the TV
even outside the app (Home/other apps), and the background overlay gains the
PIN pad (verified through the main isolate via a channel; on success offers
Add 15/30 or Switch profile, then closes). A lifecycle watcher re-raises the
overlay if another app is opened while locked.

**B. Lock-screen slideshow + switch message.** The lock screen shows a
slow-rotating background slideshow (bundled gradient scenes generated
in-app, fade transitions, no internet) plus a prominent "Switch profiles"
action. Switching requires the parent PIN, then shows the picker.

**C. Optional parent PIN.** The PIN is fully optional app-wide: if none is
set, no PIN prompt appears anywhere (unlock, switch, parent selection,
profile management all proceed directly). If set, everything stays
PIN-gated. The phone's post-pairing "Set PIN" step gains a Skip path.

**D. Daily usage records.** New `UsageRecords` table: per profile per day —
used seconds plus events (session start/end, limit hit, shutdown/turn-on).
On app start after a reboot, the previous day/session is closed out with
elapsed-to-shutdown time (monotonic delta persisted on each tick). The phone
dashboard shows today's usage per profile plus a simple per-day history
row ("Today: 25 min · Yesterday: 30 min").

## Architecture

Monorepo layout:

```text
tv_guard/
  packages/core/        # shared Dart: models, timer, storage, HTTP API types
  app/                  # the single Flutter app (TV + phone adaptive UI)
```

The app detects its form factor at startup (`device_info_plus`: Android TV
vs phone). TV build flag `LEANBACK_LAUNCHER` is set so the single APK is
launchable from the TV home screen. On TV it shows the Leanback UI described
below; on phone the management UI.

### Running on TV (source of truth)

- **Profile picker** shown at session start: user selects their profile; that
  profile's session begins (or resumes) for the day.
- **Countdown timer** runs while the app session is active. Time is measured
  with a monotonic clock (elapsed realtime), not wall clock, so changing the
  system clock does not grant extra time.
- **Reminder toasts** at remaining 15 / 10 / 5 minutes ("10 minutes left"),
  each shown once per threshold per session (see requirement 9).
- **Last-minute countdown widget** pinned top-right during the final 60
  seconds (see requirement 10); it scales responsively like the rest of the
  TV UI.
- **Full-screen overlay** when time reaches zero: an always-on-top window
  ("Time's up! Enter PIN to add time") that intercepts Back/Home. Clearing it
  requires the parent PIN (adds time) — there is no other exit while active.
- **LAN HTTP server** (`dart:io` HttpServer on a fixed port, e.g. 8477):
  the sync API. Endpoints:
  - `GET /api/state` — profiles, active session, remaining seconds, master
    lock state
  - `POST /api/profiles` / `PATCH /api/profiles/:id` — create/edit profile
    (including allowance)
  - `POST /api/time` — add time to a profile (auth: shared token + parent PIN)
  - `PUT /api/time/:profileId` — override: set a profile's remaining time
    directly (auth: shared token + parent PIN)
  - `POST /api/lock` — master lock: enable/disable all profiles at once
    (auth: shared token + parent PIN)
  - `POST /api/pair` — pairing handshake (phone sends the QR nonce; TV
    replies with the session token; nonce is single-use)
- Persistence: SQLite via Drift; survives app kill/restart.
- **Responsive, full-screen UI**: every TV screen (profile picker, countdown,
  overlay) lays out relative to the actual screen width/height — content fills
  the whole screen, text/buttons/grid scale with screen size, and the overlay
  always covers 100% of the display on any TV resolution (720p through 4K).
  No fixed-size or letterboxed layouts; use `MediaQuery`/`LayoutBuilder`
  proportions rather than pixel constants.

### Running on phone

- **Discovery & pairing**:
  - Primary: scan the TV's pairing **QR code** with the phone camera. Scanning
    is built into Eleen via the `mobile_scanner` Flutter package (in-app
    camera scanner; requires only the camera permission). The app never
    depends on or launches any other app (no external barcode-scanner apps,
    no browser, no companion apps). QR payload:
    `eleen://pair?host=<ip>&port=<port>&nonce=<one-time>` — the nonce makes
    the code single-use.
  - Fallback: NSD/mDNS (`_eleen._tcp`) discovery when the QR isn't handy.
- **Management screens**: the TV's profile list with live remaining time
  (poll `/api/state`), create/edit allowance 15/30/45/60, add time
  (PIN entry on mobile), override a profile's remaining time directly,
  and a master-lock toggle that disables all profiles on the TV.

## Data Model (owned by TV)

- **Profile**: id, name, avatar, dailyAllowanceMinutes (enum: 15/30/45/60)
- **Session**: id, profileId, date, remainingSeconds
- **Settings**: pairing token, parent PIN, masterLockEnabled flag

Daily reset: on session start (or state fetch), if the session's date is not
today, remaining time resets to the profile's configured allowance.

## Key Flows

1. **Session**: TV app opens → profile picker → profile's session runs →
   timer hits 0 → overlay locks the screen.
2. **Add time (TV)**: overlay PIN pad (D-pad navigable) → correct PIN →
   parent chooses an increment → overlay clears, timer resumes.
3. **Add time (mobile)**: profiles screen → "Add time" → PIN →
   `POST /api/time` → TV applies immediately (overlay clears if it was up).
4. **Pairing (QR code)**: TV shows a QR code encoding its pairing payload
   (LAN IP, HTTP port, one-time pairing nonce). The phone scans it with its
   camera, completes the handshake (`POST /api/pair`) with the nonce, and
   both sides store the shared session token. mDNS discovery remains as a
   fallback (find the TV without a code), but the QR code is the primary,
   one-shot pairing path — scanning an old QR code fails because each code's
   nonce is single-use.
5. **Override time (phone)**: profile list → set remaining time →
   `PUT /api/time/:profileId` → TV applies immediately.
6. **Master lock (phone)**: master-lock toggle → PIN → `POST /api/lock` →
   TV ends the active session, shows the time's-up overlay regardless of
   remaining time, and blocks all profiles until the lock is lifted from
   the phone. Lifting it restores each profile's remaining time.

## Error Handling

- Phone can't reach TV: "TV offline — check both devices are on the same
  Wi-Fi" state. LAN-only means no offline queueing; the action simply fails
  with a clear message.
- TV app killed/restarted mid-session: remaining time persisted, session
  resumes on relaunch.
- Duplicate day rollover while app is open: on date change, active session's
  date advances and time resets (rare; handled explicitly).

## Security (household-level, best effort)

- Shared pairing token on every API request; reject unknown tokens.
- Parent PIN required for any add-time or allowance-change action.
- Plain HTTP is accepted because traffic never leaves the LAN; no secrets
  beyond the token/PIN are transmitted.

## Testing

- `packages/core` unit tests: timer math, daily reset, persistence,
  allowance enum.
- HTTP API integration tests: run the server in-process and exercise all
  endpoints, including auth rejection.
- Widget tests: TV profile picker, overlay + PIN pad (focus/D-pad traversal),
  phone profiles and pairing screens.
- **End-to-end tests (integration_test / flutter drive)** covering the main
  features, run on emulators in CI:
  1. TV: create profile → set 15-min allowance → pick profile → time expires
     → overlay appears → PIN adds time → overlay clears.
  2. Phone: pair with TV by scanning its QR code → profile list shows live
     remaining time → add time → TV timer increases.
  3. Phone: override remaining time → TV reflects new value.
  4. Phone: enable master lock → TV overlay appears mid-session → disable
     lock → TV resumes with preserved remaining time.
  5. TV app killed and relaunched mid-session → remaining time persists.
  6. TV: toasts fire at 15/10/5 minutes remaining (once each), and the
     top-right countdown runs the last 60 seconds before the overlay.

## Guided Developer Steps (runbook)

Step-by-step actions from an empty machine to a published app. Each step is
verifiable; don't move on until its check passes.

1. **Prerequisites**
   - Install: Flutter SDK (stable), Android Studio (SDK + emulator images for
     both phone and Android TV), a JDK 17+.
   - Verify: `flutter doctor` → no issues; `flutter emulators` lists a TV
     emulator (create one via AVD Manager → Device Definition: Android TV,
     e.g. 1080p) and a phone emulator.
2. **First run (local)**
   - `flutter pub get` at repo root (melons workspaces, then per package).
   - Run on TV emulator: `flutter run -d <tv-emulator-id>` → confirms the app
     installs and launches from the TV home screen (LEANBACK_LAUNCHER set).
   - Run on phone emulator: `flutter run -d <phone-emulator-id>` → confirms
     phone UI.
3. **Pair & exercise the core loop (two emulators, same "LAN")**
   - Start both emulators. Note: emulators share the host network loopback —
     for LAN discovery between them, use mDNS may not work in emulators;
     fall back to manual IP entry (host loopback) or run the phone app on a
     physical device on the same Wi-Fi as a TV emulator host / real TV.
   - TV: open Pairing screen → QR shows.
   - Phone: Scan → paired → profile list appears.
   - Create a profile (15 min) on phone → TV picker shows it.
4. **Test before every commit**
   - `flutter test` (unit + widget, packages/core and app).
   - `flutter test integration_test` on the TV emulator (shortened-timer
     variant so E2E runs in seconds, not minutes — a debug flag scales all
     durations by 1/60).
   - All E2E scenarios 1–6 in the Testing section must pass.
5. **Build release artifacts**
   - `flutter build appbundle --release` → signed AAB
     (`app/build/outputs/bundle/release/`).
   - Signing: generate upload keystore (`keytool -genkey`), store in Android
     Keystore / Play App Signing; never commit the keystore or passwords —
     use `key.properties` (gitignored) or CI secrets.
6. **Publish to Google Play (one-time + per release)**
   - One-time: create Play Console account ($25), create app "Eleen",
     opt in to Play App Signing, complete the data-safety form (no data
     collected), content rating questionnaire, and add TV banner 320×180,
     feature graphic, phone screenshots, app descriptions.
   - Per release: bump version in `pubspec.yaml` → build AAB → upload to
     an internal testing track → install on real devices from the track →
     verify QR pairing and timer flow on a real TV and phone on the same
     Wi-Fi → promote to production (or staged rollout).
7. **Real-device verification checklist (pre-submit)**
   - TV: D-pad navigates every screen; overlay covers whole screen at the
     device's resolution; toasts at 10/5 min; last-minute countdown top-right;
     app relaunch resumes remaining time.
   - Phone: scan QR on real TV; profile list live-updates; override and
     master lock work; TV offline state shows clear message.

- Publish as **Eleen** on Google Play:
  - Single app listing; one release targeting both phone and Android TV
    form factors (Play handles delivery per device).
  - Signing: upload key in Play App Signing; versioning via
    `pubspec`/Gradle versionCode per build.
  - Store listing assets: TV banner (320×180), phone screenshots, feature
    graphic, content rating questionnaire, data-safety form
    (declares: no data collected — LAN-only app).
  - TV quality: app must pass Android TV quality guidelines (D-pad
    navigation, banner, no touch-only requirement) for TV listing approval.
  - CI produces signed release AAB (`flutter build appbundle`) ready for
    Play upload.
- Note: account/setup on the Play Console and the final "Submit for review"
  action are done by the developer; the build pipeline gets the artifact
  ready.
