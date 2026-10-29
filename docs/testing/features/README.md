# Cucumber feature specs

Gherkin source of truth for Eleen's end-to-end behaviour. Each feature maps
to (or extends) the executable scenarios in `app/integration_test/e2e_test.dart`.

The TV app is a parental-control dashboard: the home (profile picker +
settings row) is the only main screen. Enabling a child profile's "Enforce
time" toggle runs the session in the background; the reminder toasts,
last-minute badge and Time's-up lock render over other apps via the
SYSTEM_ALERT_WINDOW overlay. There is no countdown screen.

| Feature file | Covers | Executable coverage |
|---|---|---|
| `phone_pairing_dashboard.feature` | Home pair status icon, scan/manual pairing, dashboard | scenarios 2–4 (pairing helpers); QR camera scan is a real-device checklist item |
| `enforcement_home.feature` | Enforcement toggle, home status row (name + remaining + clock pill), last-minute badge | feature_scenarios `enforcement_home` group; e2e scenarios 1, 5, 6 |
| `times_up_screen.feature` | Time's Up overlay, add time, switch profile, toasts, last-minute, lock pauses other apps | scenarios 1, 6, 9; feature_scenarios `times_up_screen` group |
| `profile_list.feature` | Add-profile card, edit via long press, enforcement toggle, PIN gates | scenario 8 |
| `profile_form.feature` | Required name, cancel/save redirect, save errors, D-pad focus traversal, child-only | scenario 8 (partial: focus-traversal and error scenarios not yet automated) |
| `profile_switching_pin.feature` | PIN rules for enforcement toggles + add/edit, PIN set/change/remove | feature_scenarios `profile_switching_pin` group; PIN settings flows |
| `session_persistence_usage.feature` | Relaunch recovery, master lock, usage records | scenarios 4, 5, 10 |

## Decisions locked in by these specs

1. **Save failure shows a toast** — `profile_form.feature` asserts a toast
   ("Could not save the profile") that self-dismisses, with the form kept
   open and values intact. Implemented ([profile_form.dart](../../../app/lib/tv/profile_form.dart):
   SnackBar on the catch branch, inline error kept).
2. **Every profile is a child profile** — the TV never creates or edits
   parent profiles; `isParent` survives only as a wire-model field. The
   picker's management actions (enforcement toggles, add/edit) are gated by
   the parent PIN; with no PIN set they are ungated.
3. **PIN is exactly 4 digits** — implemented everywhere (TV settings pad
   caps at 4 with the "Use no more than 4 digits" error; phone dialogs use
   digitsOnly + 4-char cap; `PUT /api/pin` rejects anything but 4).

## Tags

- `@real-device` — scenarios that need real hardware (camera QR scan,
  SYSTEM_ALERT_WINDOW toast/badge render, the bring-to-front that pauses
  another app's playback). Everything else runs in the emulator harness
  (`app/integration_test/`). The `bringToFront` call is unit-tested in
  `app/test/tv_home_enforcement_test.dart` via the injectable seam.
