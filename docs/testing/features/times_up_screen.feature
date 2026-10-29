Feature: Time's Up lock screen
  When a child session expires, the TV shows the Time's Up lock screen over
  the slideshow. The parent can enter the PIN to add time or switch profile.
  The PIN pad must be fully D-pad navigable — the system numbers keyboard
  must not be forced on the user.

  Background:
    Given the TV has a child profile "Kid" with a 15 minute daily allowance
    And a parent PIN "1234" is set
    And "Kid" has an active session that has just expired
    Then the lock overlay is shown with "Time's up!"

  Scenario: Lock screen shows the slideshow and the switch hint
    Then the lock screen slideshow is visible behind the scrim
    And the hint "Enter parent PIN to add time or switch profiles" is shown

  Scenario: PIN entry is D-pad navigable without the numbers keyboard
    When the user navigates the PIN pad with the TV remote arrows
    Then every digit key can be reached and focused
    And the system numbers keyboard is not shown
    And the user can enter the full PIN using only Select/Enter on the remote

  Scenario: Add 15 minutes end to end
    When the user enters the parent PIN "1234"
    Then the add-time chooser is shown
    When the user selects "Add 15 minutes"
    Then the lock overlay closes
    And the home status row resumes at "15:00"

  Scenario: Add 30 minutes end to end
    When the user enters the parent PIN "1234"
    And the user selects "Add 30 minutes"
    Then the lock overlay closes
    And the home status row resumes at "30:00"

  Scenario: Switch profile end to end
    When the user enters the parent PIN "1234"
    And the user selects "Switch profile"
    Then the expired session ends
    And the profile picker is shown

  Scenario: The Switch profile button is visible on the lock screen
    Given "Kid" has an active session that has just expired
    And a parent PIN "1234" is set
    Then the "Switch profile" button is shown on the Time's up screen
    When the user taps "Switch profile" without entering the PIN
    Then the error "Enter the parent PIN first" is shown
    And the lock overlay stays up
    When the user enters the parent PIN "1234"
    And selects "Switch profile" from the chooser
    Then the expired session ends
    And the profile picker is shown

  Scenario: Wrong PIN is rejected
    When the user enters the PIN "000000"
    Then a PIN error is shown
    And the add-time chooser is not shown
    And the lock overlay stays up

  Scenario: No PIN set — parent actions are unlocked without a PIN
    Given no parent PIN is set
    When the lock overlay is shown with "Time's up!"
    Then the add-time chooser is offered without asking for a PIN

  Scenario: Reminder toasts fire before expiry
    Given "Kid" has an active session with 11 minutes remaining
    Then a "10 minutes left" toast appears when 10 minutes remain
    And a "5 minutes left" toast appears when 5 minutes remain
    And the toasts appear in that order

  Scenario: Last-minute countdown badge precedes the lock overlay
    Given "Kid" has an active session with 1 minute remaining
    Then the per-second last-minute countdown badge is shown
    And the lock overlay is not yet shown
    When the final minute elapses
    Then the lock overlay is shown with "Time's up!"

  @real-device
  Scenario: The last-minute countdown is visible over any running app
    Given "Kid" has an active session with 2 minutes remaining
    And the TV app is in the background while YouTube or Netflix runs
    When the session enters its final minute
    Then a live per-second countdown badge is shown over the running app
    And the badge ticks down every second
    When the parent adds time from the phone during the final minute
    Then the badge disappears and the running app stays untouched
    When the session expires
    Then the "Time's up!" lock replaces the badge

  @real-device
  Scenario: The overlay surfaces require the Display-over-other-apps permission
    Given the TV app has never been granted "Display over other apps"
    And the TV has a child profile "Kid" with a 15 minute daily allowance
    When the user turns on the "Enforce time" toggle for "Kid"
    Then the home shows a warning banner that overlays cannot cover other apps
    And the banner offers an "Allow overlays" button
    When the user selects "Allow overlays"
    Then the system "Display over other apps" screen opens for Eleen
    When the user grants the permission and returns to Eleen
    Then the banner is gone
    And reminder toasts, the last-minute badge and the lock render over other apps

  Scenario: The banner shows only while enforcement needs overlays
    Given the overlay permission is denied
    And no child profile is enforced
    Then the warning banner is not shown
    When the user enforces a child profile
    Then the warning banner is shown
    When the overlay permission is granted and the app resumes
    Then the warning banner is gone

  @real-device
  Scenario: Reminder toasts show over any running app
    Given "Kid" has an active session with 11 minutes remaining
    And the TV app is in the background while YouTube runs
    When the session crosses the 10 minute mark
    Then a reminder toast "10 minutes left" is shown over YouTube
    And YouTube stays usable (the toast is click-through)
    And the toast disappears after about 5 seconds
    When the session crosses the 5 minute mark
    Then a reminder toast "5 minutes left" is shown over YouTube

  @real-device
  Scenario: The lock takes over from a toast over another app
    Given "Kid" has an active session with 10 minutes remaining
    And the TV app is in the background while YouTube runs
    And a reminder toast "10 minutes left" is showing over YouTube
    When the session expires
    Then the toast overlay closes
    And Eleen comes to the front with the "Time's up!" lock screen
    And YouTube's playback is paused (its activity is backgrounded)
    And the lock screen's PIN pad is reachable with the remote

  @real-device
  Scenario: Time's up brings Eleen to the front over any running app
    Given "Kid" has an active session with 15 minutes remaining
    And the TV app is in the background while YouTube runs
    And no reminder toast is showing
    When the session expires
    Then Eleen comes to the front with the "Time's up!" lock screen
    And YouTube's playback is paused (its activity is backgrounded)
    And the lock guards the TV until the parent PIN is entered
    When the parent enters the PIN from the remote
    Then the add-time chooser is offered
    # Note: the interactive lock is the real activity, not a system overlay —
    # a SYSTEM_ALERT_WINDOW window cannot take TV-remote key input.

  Scenario: Time's up while the Eleen app is visible uses the in-app lock only
    Given "Kid" has an active session
    And the Eleen app is in the foreground
    When the session expires
    Then the in-app lock overlay is shown with "Time's up!"
    And no bring-to-front fires (Eleen is already in front)

  Scenario: No platform toast while the Eleen app is visible
    Given "Kid" has an active session
    And the Eleen app is in the foreground
    When the session crosses the 10 minute mark
    Then the reminder toast shows inside the Eleen app only
    And no system overlay toast is shown

  @real-device
  Scenario: Full background sequence — toasts, then the guard at expiry
    Given "Kid" has an active session with 15 minutes remaining
    And the TV app is in the background while another app runs
    When the session crosses the 10 minute mark
    Then a "10 minutes left" toast shows over the running app
    And the toast overlay closes itself after about 5 seconds
    When the session crosses the 5 minute mark
    Then a "5 minutes left" toast shows over the running app
    When the session expires
    Then the toast overlay closes
    And Eleen comes to the front with the "Time's up!" lock screen exactly once
    And the running app's playback is paused
    And the TV stays guarded until the parent PIN is entered

  Scenario: Lock overlay persists until parent action
    Given "Kid" has an active session that has just expired
    Then the lock overlay is shown with "Time's up!"
    When the user does not enter the parent PIN
    Then the lock overlay remains visible
    When the user enters the parent PIN "1234"
    Then the lock overlay closes

  @real-device
  Scenario: The lock pauses whatever app is running
    Given "Kid" has an active session that has just expired
    And the TV app is in the background while YouTube or Netflix runs
    When the lock engages
    Then the app sends the device to the launcher
    And the running app is backgrounded so its playback pauses
    And the "Time's up!" lock overlay covers the screen

  Scenario: The lock never sends the device home while Eleen is visible
    Given "Kid" has an active session
    And the Eleen app is in the foreground
    When the session expires
    Then the in-app lock overlay is shown with "Time's up!"
    And the app does not send the device to the launcher

  Scenario: Lock overlay closes after adding time
    Given "Kid" has an active session that has just expired
    Then the lock overlay is shown with "Time's up!"
    When the user enters the parent PIN "1234"
    And the user selects "Add 15 minutes"
    Then the lock overlay closes
    And the home status row resumes at "15:00"

  Scenario: Lock overlay closes after switching profile
    Given "Kid" has an active session that has just expired
    Then the lock overlay is shown with "Time's up!"
    When the user enters the parent PIN "1234"
    And the user selects "Switch profile"
    Then the expired session ends
    And the home status row disappears

  Scenario: No PIN set — add-time chooser is available without a PIN
    Given no parent PIN is set
    When the lock overlay is shown with "Time's up!"
    Then the add-time chooser is offered without asking for a PIN

  Scenario: No PIN set — lock overlay is shown without a PIN
    Given no parent PIN is set
    When the lock overlay is shown with "Time's up!"
    Then the lock overlay is visible without asking for a PIN

  Scenario: No PIN set — lock overlay closes after adding time without a PIN
    Given no parent PIN is set
    When the lock overlay is shown with "Time's up!"
    And the user selects "Add 15 minutes"
    Then the lock overlay closes
    And the home status row resumes at "15:00"

  Scenario: No PIN set — switch profile is available without a PIN
    Given no parent PIN is set
    When the lock overlay is shown with "Time's up!"
    And the user selects "Switch profile"
    Then the expired session ends
    And the profile picker is shown

  Scenario: No PIN set — lock overlay closes after switching profile without a PIN
    Given no parent PIN is set
    When the lock overlay is shown with "Time's up!"
    And the user selects "Switch profile"
    Then the expired session ends
    And the profile picker is shown
