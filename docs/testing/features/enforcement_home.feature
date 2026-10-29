Feature: Enforcement home status
  The TV home (profile picker + settings row) is the only main screen. There
  is no countdown screen: enabling a child profile's enforcement runs the
  session in the background while the home stays up, and a compact status row
  at the top shows who is enforced and how long is left, alongside the
  wall-clock time.

  Background:
    Given the TV has a child profile "Kid" with a 15 minute daily allowance
    And a parent PIN "1234" is set

  Scenario: Enabling enforcement keeps the home and shows the status row
    When the parent turns on the "Enforce time" toggle for "Kid"
    And enters the parent PIN "1234"
    Then the home is still shown with the profile picker and the settings row
    And the status row shows the profile name "Kid"
    And the status row shows the live remaining time
    And the wall-clock time pill is shown in the status row
    And no countdown screen is shown

  Scenario: The status row is absent while nothing is enforced
    Given no profile is enforced
    Then the home shows the profile picker
    And no status row is shown

  Scenario: The status row ticks down while the session runs
    Given "Kid" is enforced
    Then the status row remaining time decreases every second
    And the wall-clock pill tracks the current time of day in h:mm AM/PM

  Scenario: Enforcing a second profile ends the first
    Given "Kid" is enforced
    And the TV also has a child profile "Sam"
    When the parent turns on the "Enforce time" toggle for "Sam"
    Then "Kid"'s session ends
    And only "Sam" is enforced

  Scenario: Turning enforcement off ends the session
    Given "Kid" is enforced
    When the parent turns off the "Enforce time" toggle for "Kid"
    Then the session ends
    And the status row disappears

  Scenario: Enforcement is gated by the parent PIN
    Given a parent PIN "1234" is set
    When the parent turns on the "Enforce time" toggle for "Kid"
    Then the parent PIN prompt is shown before any session starts
    When the parent enters the wrong PIN
    Then a PIN error is shown and no session starts
    When the parent enters the correct PIN "1234"
    Then "Kid" is enforced

  Scenario: With no PIN set, enforcement is ungated
    Given no parent PIN is set
    When the parent turns on the "Enforce time" toggle for "Kid"
    Then "Kid" is enforced without a PIN prompt

  Scenario: The last-minute badge appears in the final minute
    Given "Kid" is enforced with 1 minute remaining
    Then the per-second last-minute badge is shown in the status row
    And the live remaining time is still shown
    And the lock overlay is not yet shown
    When the final minute elapses
    Then the lock overlay is shown with "Time's up!"

  Scenario: The overlay permission status chip is shown on the home
    Given the "Display over other apps" permission is granted
    Then the settings row shows the "Overlays allowed" status chip
    And no permission banner is shown
    And tapping the chip opens the system permission screen

  @real-device
  Scenario: The status chip turns red while the permission is revoked
    Given the "Display over other apps" permission is revoked
    When the app resumes
    Then the status chip shows "Overlays blocked"
