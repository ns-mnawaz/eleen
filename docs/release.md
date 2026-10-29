# Eleen — Release runbook

Everything needed to go from a clean checkout to a Play Console upload and
staged rollout. Concrete commands; no CI pipeline is wired up — this is a
manual runbook (see "Running E2E / CI notes" below for how the E2E suite is
run today).

## 1. Versioning

The single source of truth is `app/pubspec.yaml`:

```yaml
version: 1.0.0+1   # versionName+versionCode
```

`versionName` is the user-visible version (`1.0.0`); `versionCode` is the
monotonic integer after `+` (`1`). The Flutter Gradle plugin forwards both
into `android/app/build.gradle.kts` (`flutter.versionCode` /
`flutter.versionName`) — never edit versionCode/versionName in Gradle.

**Every release bumps both:** `version: 1.0.1+2`, etc. Play rejects an
upload whose versionCode is not higher than the live one.

## 2. Release signing (upload keystore)

Release credentials come from `app/android/key.properties` (gitignored;
committed template: `app/android/key.properties.example`):

```properties
storeFile=/absolute/path/to/eleen-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Generate the keystore once, **outside the repo**, and back it up:

```sh
keytool -genkeypair -v -keystore eleen-upload.jks -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

- Losing this keystore means you cannot update the app — back it up with the
  passwords (password manager / secure storage).
- `storeFile` may be absolute or relative to `app/android/`.
- **Graceful degradation:** if `key.properties` is absent, the release build
  falls back to the debug signing config so a fresh clone still builds.
  Debug-signed output is fine for local development only — never upload it.
- The E2E/verification build for this plan used a locally generated TEST
  keystore (`eleen-upload-test.jks`, same keytool command); replace it with
  the real upload keystore before any store upload.

**Play App Signing:** on first upload, enroll in Play App Signing (Play
Console → Release → Setup → App signing). Google keeps the *app signing
key*; your upload keystore above is only the *upload key*. Optional hardening
after enrollment: reset the upload key or request an upload-key reset via
Play Console support if it ever leaks.

## 3. Build the release AAB

```sh
cd app
flutter pub get
flutter build appbundle --release
```

Output: `app/build/app/outputs/bundle/release/app-release.aab`
(gitignored — do not commit it).

Verify what signed it:

```sh
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

Expected owner: your upload key's CN (the test run showed
`CN=Eleen Test Upload, …`). If it says `CN=Android Debug`, `key.properties`
was not picked up — check the path and re-run.

## 4. Store listing checklist

Play Console → the app entry:

- [ ] **App name / short / full descriptions**, category (e.g. Parenting or
      Tools), contact email.
- [ ] **TV banner 320×180** — source of truth:
      `app/android/app/src/main/res/drawable/tv_banner.png` (placeholder is
      in place; replace with final art, same path, keep 320×180 PNG).
- [ ] **Feature graphic** 1024×500 and **app icon** 512×512 (Play Console
      assets; not shipped in the APK).
- [ ] **Phone screenshots** (2+ PNGs, 16:9 or 9:16) — capture the phone
      profiles dashboard, pairing screen, and add-time UI.
- [ ] **TV screenshots** (1+, 16:9, 1920×1080) — TV home with session timer
      and the lock overlay.
- [ ] **Data safety form:** *No data collected, no data shared.* Eleen is
      LAN-only: all sync traffic stays on the local network between the TV
      and the phone app; there are no analytics, no ads, no remote servers.
      No encryption-in-transit-at-rest declarations needed beyond that.
- [ ] **Content rating questionnaire** (IARC): no user-generated content
      shared publicly, no online interactions outside the household LAN,
      no ads → expect Everyone / low rating.
- [ ] **Privacy policy URL** — still required by Play even with "no data
      collected"; host a one-pager stating LAN-only operation.
- [ ] **Target audience** settings; no age-restricted content.

### Android TV quality gates

- [ ] D-pad navigation works on every TV screen (no touch-only requirement;
      verified in E2E scenarios 1–6 via the `eleen_tv` AVD).
- [ ] TV banner renders in the launcher (LEANBACK_LAUNCHER intent + banner
      resource).
- [ ] Declare `android.software.leanback` feature (not required) and keep
      the touchscreen feature not-required so TV Play shows the app.
- [ ] Landscape layout, no portrait-only assumptions on TV.
- [ ] Test the full flow on a real TV before promoting (step 6).

## 5. Upload to the internal test track

1. Play Console → Testing → Internal testing → create release.
2. Upload `app-release.aab` from step 3.
3. Add internal testers (email lists), share the opt-in link.
4. Install on **real devices** from the test track:

**Real-device verification gate (do not skip):**

- [ ] TV + phone on the **same Wi-Fi** (LAN sync only — confirm no hotspot
      / VPN / guest-network isolation between them).
- [ ] Phone app: scan the TV's **QR code** → pairing succeeds.
- [ ] TV: start a session, let it run to the lock overlay.
- [ ] Phone: add time via the override → TV overlay clears, timer resumes.
- [ ] Phone: master lock on → TV locks immediately; lock off → remaining
      time preserved.

## 6. Promote / staged rollout

1. Internal testing → verified (step 5 checklist all green).
2. Promote: Testing → Closed → Production, or create the Production release
   directly from the same AAB.
3. **Staged rollout:** start at 10%, watch Play Console vitals + crash
   reports, then 50% → 100%. The app collects no data, so there is no
   backend rollout to coordinate — a bad release is rolled back by halting
   the rollout and uploading a `versionCode+1` fix.

## Running E2E / CI notes

The 6/6 E2E suite (Task 14) runs against the `eleen_tv` AVD
(Android 14, device id `emulator-5554`). A **cold CI environment must boot
the emulator first**; the AVD was already booted in the original session.

```sh
# one-time per emulator boot: grant CAMERA so the real MobileScanner on the
# QR screen initializes without a runtime dialog
adb shell pm grant com.eleen.eleen android.permission.CAMERA

# all six scenarios in one invocation (~1 min; first Gradle build of a
# session adds ~2-3 min):
cd app && flutter test integration_test/e2e_test.dart --dart-define=ELEN_FAST=1 -d emulator-5554

# per-form-factor passes:
cd app && flutter test integration_test/e2e_test.dart --dart-define=ELEN_FAST=1 --dart-define=ELEEN_FORM=tv -d emulator-5554
cd app && flutter test integration_test/e2e_test.dart --dart-define=ELEN_FAST=1 --dart-define=ELEEN_FORM=phone -d emulator-5554
```

CI, if/when wired up, needs: `flutter emulators --launch eleen_tv` + wait
for `sys.boot_completed` (or `avdmanager`/`emulator -avd eleen_tv -no-window
-no-audio -gpu swiftshader_indirect`), the CAMERA grant above, then the test
command. Real QR scanning remains out of scope on the emulator — the manual
code fallback drives pairing in scenarios.
