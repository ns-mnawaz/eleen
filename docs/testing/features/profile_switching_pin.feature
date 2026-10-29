Feature: PIN rules for managing profiles
  The parent PIN gates management on the TV: enabling or disabling a child
  profile's enforcement, and opening the add/edit form. There are no parent
  profiles any more — every profile is a child. With no PIN set, every
  management action is ungated.

  Background:
    Given the TV has the child profiles "Maya" and "Leo"

  Rule: No PIN set — nothing is gated

    Scenario: Enabling enforcement with no PIN set
      Given no parent PIN is set
      When the parent turns on the "Enforce time" toggle for "Maya"
      Then "Maya" is enforced without a PIN prompt

    Scenario: Adding a profile with no PIN set
      Given no parent PIN is set
      When the parent selects "Add profile"
      Then the profile form opens without a PIN prompt

  Rule: PIN set — management actions are gated

    Scenario: Enabling enforcement asks for the PIN
      Given a parent PIN "1234" is set
      When the parent turns on the "Enforce time" toggle for "Maya"
      Then the parent PIN prompt is shown before any session starts
      And no session starts behind the prompt

    Scenario: Wrong PIN keeps the gate closed
      Given a parent PIN "1234" is set
      When the parent turns on the toggle for "Maya" and enters "0000"
      Then a PIN error is shown
      And the PIN prompt stays open
      And no session starts

    Scenario: Correct PIN starts enforcement
      Given a parent PIN "1234" is set
      When the parent turns on the toggle for "Maya" and enters "1234"
      Then "Maya" is enforced

    Scenario: Disabling enforcement asks for the PIN too
      Given a parent PIN "1234" is set
      And "Maya" is enforced
      When the parent turns off the "Enforce time" toggle for "Maya"
      Then the parent PIN prompt is shown before the session ends

    Scenario: Adding and editing profiles are gated
      Given a parent PIN "1234" is set
      When the parent selects "Add profile"
      Then the parent PIN prompt is shown
      When the parent enters the correct PIN "1234"
      Then the profile form opens
      When the parent long-presses "Maya"
      And enters the correct PIN "1234"
      Then the edit form opens with the name prefilled

  Rule: PIN management from the TV

    Scenario: Set a PIN for the first time requires confirmation
      Given no parent PIN is set
      When the parent opens Parent PIN settings
      Then the set flow starts immediately with "Set a parent PIN"
      When the parent enters "1234" and confirms with "4321"
      Then the error "PINs do not match" is shown
      When the parent enters "1234" and confirms with "1234"
      Then the PIN is saved

    Scenario: New PIN must be exactly 4 digits
      Given no parent PIN is set
      When the parent enters a 3-digit PIN in the set flow
      Then the error "Use at least 4 digits" is shown
      And the PIN pad accepts no more than 4 digits
      When the parent enters "12345"
      Then the entry shows 4 digits only

    Scenario: The 4th digit moves focus to the action button
      Given no parent PIN is set
      And the parent is in the set flow
      When the parent enters the 4th digit
      Then D-pad focus moves to the Next button
      So a single Select press advances the flow

    Scenario: Phone PIN fields advance focus at 4 digits
      Given the parent is setting the parent PIN on the phone
      When the parent types the 4th digit of the PIN
      Then focus moves to the Confirm PIN field
      When the parent types the 4th digit of the confirmation
      Then focus moves to the "Save PIN" button
      And Enter or Select submits the PIN

    Scenario: Change PIN requires the current PIN
      Given a parent PIN "1234" is set
      When the parent opens Parent PIN settings and chooses "Change PIN"
      And enters the wrong current PIN
      Then the error "Wrong PIN" is shown
      When the parent enters the current PIN "1234" and a matching new PIN
      Then the new PIN is saved and gates subsequent management actions

    Scenario: Remove PIN returns the TV to the no-gate behaviour
      Given a parent PIN "1234" is set
      When the parent opens Parent PIN settings and chooses "Remove PIN"
      And enters the current PIN "1234"
      Then the PIN is removed
      And enabling enforcement no longer asks for a PIN

    Scenario: Remove PIN requires the current PIN
      Given a parent PIN "1234" is set
      When the parent opens Parent PIN settings and chooses "Remove PIN"
      And enters the wrong current PIN
      Then the error "Wrong PIN" is shown
      And the PIN is not removed

    Scenario: Remove PIN is not allowed if no PIN is set
      Given no parent PIN is set
      When the parent opens Parent PIN settings
      Then the option to remove the PIN is not available

    Scenario: Change PIN is not allowed if no PIN is set
      Given no parent PIN is set
      When the parent opens Parent PIN settings
      Then the option to change the PIN is not available

    Scenario: All PIN in APP should be of 4 digits
      Given no parent PIN is set
      When the parent enters a 3-digit PIN
      Then the error "Use at least 4 digits" is shown
      When the parent enters a 5-digit PIN
      Then the error "Use no more than 4 digits" is shown

    Scenario: Changing PIN to the same as the current PIN is not allowed
      Given a parent PIN "1234" is set
      When the parent opens Parent PIN settings and chooses "Change PIN"
      And enters the current PIN "1234"
      And enters the new PIN "1234"
      Then the error "New PIN must be different from the current PIN" is shown
      When the parent enters a different new PIN
      Then the new PIN is accepted
