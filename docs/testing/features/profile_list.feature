Feature: Profile list on the TV picker
  The TV profile picker lists every child profile with its "Enforce time"
  toggle, exposes Add profile, and gates management actions behind the parent
  PIN. Set/Change PIN is reachable from the picker settings area.

  Background:
    Given the TV has the child profiles "Maya" and "Leo"
    And a parent PIN "1234" is set
    And the profile picker is shown

  Scenario: Add profile button is visible
    Then the "Add profile" card is visible on the picker

  Scenario: All profiles are visible with their remaining time and toggle
    Then a card for "Maya" is shown with its remaining time
    And a card for "Maya" carries an "Enforce time" toggle
    And a card for "Leo" is shown with its remaining time

  Scenario: Add profile is PIN gated
    When the user selects "Add profile"
    Then the parent PIN prompt is shown
    When the user enters a wrong PIN
    Then a PIN error is shown and the profile form does not open
    When the user enters the correct PIN "1234"
    Then the profile form opens in create mode

  Scenario: Edit a profile via long press
    When the user long-presses the "Maya" card
    And enters the correct PIN "1234"
    Then the profile form opens in edit mode
    And the name field is prefilled with "Maya"

  Scenario: Edited profile is reflected on the picker and persisted
    Given the user is editing "Maya" in the profile form
    When the user changes the daily allowance to 15 minutes and saves
    Then the picker shows "Maya" with "Remaining 15m 00s"
    And the persisted profile "Maya" has a 15 minute allowance
    And the phone sees the same change on its next poll

  Scenario: The form is child-only
    When the profile form opens
    Then the daily allowance chips are shown
    And no "Parent profile" toggle is offered

  Scenario: Set PIN is reachable from the picker settings
    When the user opens the settings row on the TV home
    Then "Parent PIN" settings are available
    When a parent PIN is set or changed
    Then the enforcement toggles and add/edit actions use the new PIN

  Scenario: No PIN set — management asks for no PIN
    Given no parent PIN is set
    When the user selects "Add profile"
    Then the profile form opens without a PIN prompt
    When the user turns on the "Enforce time" toggle for "Maya"
    Then "Maya" is enforced without a PIN prompt
