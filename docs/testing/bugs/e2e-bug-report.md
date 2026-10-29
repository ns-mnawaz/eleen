# E2E bug report — cucumber feature scenarios

Date: 2026-10-25
Suite: `app/integration_test/feature_scenarios_test.dart` (executable form of
`docs/testing/features/*.feature`), run on the `eleen_tv` emulator
(960×540, Android 14) with `--dart-define=ELEN_FAST=1`.

Final run results (run 3, with the new PIN-validation scenarios added):
**phone pass 3/3 green**; **TV pass 12/24** — every TV failure mapped to one of
the 9 confirmed bugs below. Earlier runs: run 1 phone 3/3, TV 7/16; run 2
phone 3/3, TV 11/20 (all 4 lock-overlay scenarios passed, no regressions).

**RESOLUTION (2026-10-25, commit `c9ff470`): all 9 bugs fixed.** After the
fixes, an independent QA agent re-ran every suite: feature scenarios TV
24/24 and phone 3/3, e2e_test TV 7/7 and phone 3/3, core 131/131,
`flutter analyze` clean.

Two non-blocking risks the QA pass flagged are ALSO FIXED (with e2e/unit
coverage):
1. **Server 4-digit maximum (fixed)** — `PUT /api/pin` now rejects pins
   longer than 4 with 400 (`_setPin`). Covered by a core server test
   (rejects `12345`, nothing persisted) and a phone e2e scenario (API
   client `setPin('12345')` → `EleenApiError`, PIN unchanged).
2. **Legacy >4-digit PIN lockout (fixed)** — the TV PIN-settings
   `current` stage now caps entry at the STORED PIN's length (not 4), so a
   pre-rule database can still be matched in Change/Remove. Covered by a
   TV e2e scenario (6-digit seeded PIN proceeds to "Enter the new PIN").

The two pre-existing time-drift unit failures in
`app/test/usage_rows_test.dart` are fixed too: history dates are now
derived from the real clock (normalized to the day) instead of the
hardcoded `DateTime(2026,10,24)`; suite 5/5 green.

---

## BUG-1 — Profile form never takes D-pad focus; the picker behind it keeps it

- **Spec:** profile_form.feature — "Form opens without summoning the keyboard"
- **Evidence (CONFIRMED):** scenarios *form opens with focus on the first
  avatar chip* and *D-pad Down from the avatar chips* both fail: after the
  form route opens (and after letting the route transition settle),
  `FocusManager.primaryFocus` is still `profile-card-e2e-kid` (the picker card
  **behind** the modal form) instead of `profile-form-first-avatar`; arrow
  keys then traverse the picker, never the form's fields.
- **Impact:** on a real TV the D-pad drives the profile picker underneath the
  form — selecting a card would start a session while the parent is mid-form.
  Touch users are unaffected, which is why this survived manual testing.
- **Root cause (code review):** the picker hands focus over explicitly
  before showing its PIN gate ([profile_picker.dart:109](../../app/lib/tv/profile_picker.dart#L109)
  `primaryFocus?.unfocus()`), but `_openForm` pushes the form **without
  unfocusing** — the activated card keeps primary focus, so the form's avatar
  `autofocus` is a no-op (the exact failure mode the gate comment warns
  about).
- **Fix direction:** call `FocusManager.instance.primaryFocus?.unfocus()`
  in `_openForm` before `Navigator.push` (one line, mirrors the gate path).

## BUG-2 — PIN settings action row renders off-screen (540p TVs) — CONFIRMED

- **Spec:** profile_switching_pin.feature — set/change/remove PIN flows.
- **Evidence:** in every PIN-settings scenario, tapping `pin-settings-next`
  warns *"derived an Offset (Offset(523.3, 594.9)) that would not hit test …
  outside the bounds of the root … Size(960.0, 540.0)"* — the **Cancel/Next
  buttons sit ~55 px below the visible area** on a 960×540 TV. Taps miss;
  the Next handler never runs, so no error text / confirm stage ever appears.
  All three set-flow scenarios (min-4 error, confirm stage, "Wrong PIN",
  "PIN removed") fail on this single layout bug.
- **Impact:** touch users cannot complete any PIN management on 540p TVs at
  all. D-pad users may reach the buttons only if focus-driven scrolling
  engages.
- **Fix direction:** reduce paddings/sizes at small heights or drop the
  `SizedBox` spacers below the pad; the action row must stay inside
  `constraints.maxHeight`.

## BUG-3 — Lock overlay PIN pad '0' row is clipped off-screen (540p TVs) — CONFIRMED

- **Spec:** times_up_screen.feature — PIN entry from the remote.
- **Evidence:** in the wrong-PIN scenario, tapping `pin-key-0` warns
  *"Offset(480.0, 541.5) … outside the bounds of the root … Size(960.0,
  540.0)"* — the '0' cell's center is below the 540 px fold. The entry for a
  6-digit attempt then has only 5 digits → stays `incomplete` → no `pin-error`
  is ever shown (the assertion fails not because the check is broken but
  because the digit physically can't be tapped).
- **Impact:** any parent PIN containing the digit **0 cannot be entered by
  touch** on a 540p TV; the wrong-PIN rejection path is also unreachable
  for such PINs. The `SingleChildScrollView` hides the problem only if the
  user knows to scroll a PIN pad.
- **Fix direction:** same as BUG-2 — the pad + message column must fit the
  viewport (`MediaQuery`-proportional sizes are already used; the
  accumulated `SizedBox` spacers overflow at 540 px).

## BUG-4 — Parent PIN has no maximum length (spec: exactly 4 digits) — CONFIRMED

- **Spec decision (2026-10-24):** PIN set flow enforces min 4 **and max 4**.
- **Evidence:** scenario *the pad accepts at most 4 digits* fails: entering
  `12345` shows `•••••` (five bullets) — the pad happily accepts a 5th digit
  and the flow would save a 5-digit PIN.
- **Impact:** PINs of unbounded length can be set; every later PIN prompt
  then demands that many presses on the remote.
- **Fix direction:** cap `_entry.length < 4` in `_onDigit`
  ([pin_settings.dart](../../app/lib/tv/pin_settings.dart)) and in the
  picker/overlay PIN gates for consistency.

## BUG-5 — Save failure shows an inline error, not a toast (spec divergence)

- **Spec decision:** profile create/edit failure must surface a toast.
- **Evidence:** the scenario *save failure surfaces a toast and keeps the form
  open* — with a genuinely failing write (db in a nonexistent directory) the
  form correctly stays open with its values intact, but **no SnackBar with
  "Could not save the profile" appears**; [profile_form.dart](../../app/lib/tv/profile_form.dart)
  renders `_error` as an inline `profile-form-error` Text instead.
- **Fix direction:** `ScaffoldMessenger.showSnackBar('Could not save the
  profile: …')` in the catch branch, keeping the inline error optional.

## BUG-7 — No "no more than 4 digits" rejection (extends BUG-4) — CONFIRMED

- **Spec:** profile_switching_pin.feature — "All PIN in APP should be of 4
  digits": a 5-digit entry must show *"Use no more than 4 digits"*.
- **Evidence:** scenario *a 5-digit new PIN is rejected with "Use no more
  than 4 digits"* fails: entering `12345` shows no such error (the pad
  silently accepts the 5th digit — see BUG-4 — and Next would save it).
- **Fix direction:** cap `_entry.length < 4` in `_onDigit` **and** validate
  `length > 4 → 'Use no more than 4 digits'` in `_next`.

## BUG-8 — Changing the PIN to the same value is accepted — CONFIRMED

- **Spec:** profile_switching_pin.feature — "Changing PIN to the same as the
  current PIN is not allowed": must show *"New PIN must be different from
  the current PIN"*.
- **Evidence:** scenario *changing the PIN to the same value is rejected*
  fails: [pin_settings.dart](../../app/lib/tv/pin_settings.dart) has no
  same-value check — the change flow accepts old==new and "saves" it.
- **Fix direction:** in the `newPin` stage, compare against `_storedPin` and
  reject with the spec message.

## BUG-9 — Phone PIN fields accept non-numeric and any-length input — CONFIRMED (code review)

- **Spec:** profile_switching_pin.feature — "Entering a non-numeric PIN is
  not allowed" (the TV pad is digits-only, so this spec is only reachable
  on the phone).
- **Evidence:** [pin_dialog.dart:155](../../app/lib/phone/widgets/pin_dialog.dart#L155)
  and [set_pin_dialog.dart:107-118](../../app/lib/phone/widgets/set_pin_dialog.dart#L107-L118)
  set `keyboardType: TextInputType.number` but have **no
  `FilteringTextInputFormatter.digitsOnly` and no exact-4 validation** — a
  hardware keyboard, clipboard paste, or autofill can submit letters and
  any length.
- **Fix direction:** `inputFormatters: [FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(4)]` plus a submit-time exact-4 check.

## Resolved during diagnosis — D-pad-only PIN entry on the lock overlay

- Not a bug. The first run's failure was a wrong digit path in the test
  itself (down from '3' lands on '6', not '4'). With the corrected
  arrows+Select path, entering the full PIN and reaching the add-time
  chooser passes — the PIN pad is fully D-pad navigable as specced.

---

## Test-harness corrections made while diagnosing (not app bugs)

1. Cancel→picker: the form route is still animating out when the picker
   first appears; the test now waits for the form to be gone.
2. Phone relaunch: "Scan TV code" is **always** visible (the re-pair
   affordance, see phone_home.dart) — the test wrongly expected it gone.
3. "Closed drift db" does not fail writes — a drift `LazyDatabase` re-opens
   after close. The failing-save scenario now uses a db in a nonexistent
   directory so every write genuinely throws.
4. Two `flutter test` passes must not target the same emulator concurrently
   (killed the first TV run).

## Scenarios not automatable on the emulator (real-device checklist)

- Camera QR scanning (4 `@real-device` scenarios in
  phone_pairing_dashboard.feature) — needs a real camera.
- SYSTEM_ALERT_WINDOW overlay rendering.
