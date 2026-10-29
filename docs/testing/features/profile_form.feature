Feature: Add/Edit profile form
  The profile form validates the name, navigates correctly on cancel and
  save, surfaces save errors, and traverses fields with the TV remote
  without trapping the user in a keyboard focus loop.

  Background:
    Given a parent PIN "1234" is set
    And the user opened the profile form from the picker with the correct PIN

  Rule: Name is a required field

    Scenario: Saving with an empty name is rejected
      Given the name field is empty
      When the user presses "Create"
      Then the form stays open
      And the error "Enter a name" is shown
      And no profile is created

    Scenario: Whitespace-only name is treated as empty
      Given the name field contains only spaces
      When the user presses "Create"
      Then the error "Enter a name" is shown

  Rule: Navigation on cancel and save

    Scenario: Cancel returns to the profiles list without saving
      Given the user entered the name "TestKid"
      When the user presses "Cancel"
      Then the profiles list screen is shown
      And no profile "TestKid" exists

    Scenario: Create redirects to the profiles list on success
      When the user enters the name "TestKid"
      And selects a daily allowance of 30 minutes
      And presses "Create"
      Then the profiles list screen is shown
      And a card for "TestKid" is shown with "Remaining 30m 00s"

    Scenario: Save in edit mode redirects to the profiles list on success
      Given the user is editing the existing profile "Kid"
      When the user presses "Save"
      Then the profiles list screen is shown
      And the profile "Kid" reflects the edits

  Rule: Save failures show a toast, and the form stays open

    Scenario: Show a toast when create fails
      Given the profile service will fail to create the profile
      When the user enters the name "TestKid" and presses "Create"
      Then a toast message "Could not save the profile" is shown
      And the form stays open
      And no profile "TestKid" is created
      And the user can retry saving

    Scenario: Show a toast when edit fails
      Given the user is editing the existing profile "Kid"
      And the profile service will fail to save
      When the user presses "Save"
      Then a toast message "Could not save the profile" is shown
      And the form stays open
      And the profile "Kid" is unchanged

    Scenario: The error toast dismisses itself and the form is still usable
      Given a save failure toast is showing
      When the toast times out
      Then the toast is gone
      And the form is still open with the entered values intact

  Rule: TV remote focus traversal never traps the user

    Scenario: Form opens without summoning the keyboard
      When the profile form opens
      Then the name field is not focused
      And the on-screen keyboard is not shown
      And the first avatar chip has focus

    Scenario: Done on the keyboard moves focus to the next field
      Given the name field is focused and the keyboard is visible
      When the user enters "TestKid" and presses Done on the keyboard
      Then the keyboard closes
      And focus moves to the first avatar chip
      And focus does not return to the name field

    Scenario: D-pad traversal visits every field and action exactly once
      When the user presses the remote Down key repeatedly
      Then focus moves through name, avatars, parent toggle, allowance chips, Cancel and Create in order
      And focus never bounces back to the name field
      And the keyboard is not re-summoned by arrow navigation

    Scenario: Selecting the name field again still works after traversal
      Given the user traversed to the avatar chips with the remote
      When the user moves focus back to the name field and presses Select
      Then the keyboard opens for the name field
      And pressing Done returns focus to the avatar chips

    Scenario: Focus never gets stuck in a loop on the name field
      Given the name field is focused and the keyboard is visible
      When the user presses Done on the keyboard
      And presses the remote Down key 10 times in a row
      Then focus reaches the Cancel and Create buttons
      And focus never returns to the name field on its own
      And the keyboard is never re-summoned by arrow navigation

    Scenario: Focus wraps predictably at the ends of the form
      Given focus is on the Create button
      When the user presses the remote Down key
      Then focus moves to the first focusable field
      And no field is skipped
      And no field is visited twice in one pass

    Scenario: Up traversal mirrors Down traversal
      When the user presses the remote Up key repeatedly from the bottom action
      Then focus moves through the fields in exact reverse order
      And focus lands on the name field without opening the keyboard

  Rule: Every profile is a child profile

    Scenario: A 5 minute daily allowance is offered and works end to end
      When the user enters the name "QuickKid"
      And selects a daily allowance of 5 minutes
      And presses "Create"
      Then the profiles list screen is shown
      And a card for "QuickKid" is shown with "Remaining 5m 00s"
      And the persisted profile "QuickKid" has a 5 minute allowance
      When the parent enables enforcement for "QuickKid"
      And the 5 minutes run out
      Then the lock overlay is shown with "Time's up!"

    Scenario: The form is child-only
      When the profile form opens
      Then the daily allowance chips are always shown
      And no "Parent profile" toggle is offered

  Scenario: Form actions stay reachable on wide TVs with a floating keyboard
    Given the TV is in a wide landscape layout
    When the on-screen keyboard is visible
    Then the Cancel and Create buttons are not covered by the floating keyboard
