Feature: Session persistence, master lock and usage records
  Additional end-to-end coverage derived from the engine: relaunch
  recovery, the phone-driven master lock, and usage bookkeeping. These
  cover the regression-prone paths not visible in a single screen.

  Background:
    Given the TV has a child profile "Kid" with a 15 minute daily allowance
    And a parent PIN "1234" is set

  Rule: The session runs in the background

    Scenario: A child session keeps the app alive in the background
      Given "Kid" is enforced
      And the TV app is in the background while another app runs
      Then the session foreground service is running
      And the per-second remaining time keeps ticking behind the other app
      When the session ends (enforcement turned off or master lock)
      Then the foreground service stops

    Scenario: The locked session keeps the foreground service
      Given "Kid" has an active session that has just expired
      Then the lock overlay is shown
      And the foreground service keeps running until the session truly ends
      When the parent adds time
      Then the remaining time resumes ticking in the background

    Scenario: A suspended process is billed in full on its next tick
      Given "Kid" has an active session
      And the OS suspends the app for 10 minutes
      When the app resumes and its next tick runs
      Then the full suspended gap is charged to the session
      And the session expires if the gap exhausted the allowance

  Rule: Sessions survive a relaunch

    Scenario: Relaunch mid-session resumes the remaining time
      Given "Kid" has an active session that has burned 3 minutes
      When the TV app is closed and relaunched
      Then the home shows the status row for "Kid"
      And the remaining time resumes at no more than the persisted remainder
      And the resumed session keeps counting down

    Scenario: Relaunch after expiry comes back locked
      Given "Kid"'s session has expired
      When the TV app is closed and relaunched
      Then the lock overlay is shown again with "Time's up!"

  Rule: Usage is recorded honestly

    Scenario: Expiry records session start and limit hit
      Given "Kid"'s session has just expired
      Then today's usage for "Kid" is capped at the 15 minute allowance
      And the usage events are "sessionStart" followed by "limitHit"

    Scenario: Relaunch records a shutdown and power-on pair with no phantom time
      Given "Kid"'s session has expired
      When the TV app is closed and relaunched
      Then a "shutdown" then "powerOn" event pair is recorded
      And today's usage for "Kid" did not increase during the downtime

    Scenario: Phone dashboard shows today's usage from the TV
      Given "Kid"'s session has expired
      And the phone is paired with the TV
      When the user opens the profiles screen on the phone
      Then the row for "Kid" shows today's used minutes

  Rule: Master lock

    Scenario: Master lock locks the TV for every profile
      Given the phone is paired with the TV
      And "Kid" has an active session with 15 minutes remaining
      When the user turns the master lock on from the phone and confirms the PIN
      Then the server reports the master lock enabled
      And the active session is deactivated with remaining time untouched
      And the TV shows "Locked by parent" with no PIN pad and no unlock affordance

    Scenario: Unlocking the master lock restores the preserved session
      Given the master lock is on with "Kid"'s session preserved at 15 minutes
      When the user turns the master lock off from the phone and confirms the PIN
      Then the server reports the master lock disabled
      And "Kid"'s session is active again with 15 minutes remaining

  Rule: Phone add-time and override are PIN gated and consistent

    Scenario: Add time from the phone updates the TV state
      Given the phone is paired with the TV
      When the user taps "Add time" for "Kid", confirms the PIN and picks 15 minutes
      Then the dashboard shows "30:00 left"
      And the server reports 1800 seconds remaining for "Kid"

    Scenario: Override remaining time from the phone
      Given the phone is paired with the TV
      When the user taps "Override" for "Kid", confirms the PIN and picks 5 minutes
      Then the dashboard shows "5:00 left"
      And the server reports 300 seconds remaining for "Kid"

    Scenario: Phone actions reject a wrong PIN
      Given the phone is paired with the TV
      When the user taps "Add time" and enters a wrong PIN
      Then the add-time picker does not open
      And the remaining time is unchanged
