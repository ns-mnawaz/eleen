Feature: Phone home, pairing and dashboard
  The phone home screen reflects whether the phone is paired with a TV,
  lets the parent pair by scanning the TV's QR code or entering the manual
  code, and opens the dashboard once paired.

  Background:
    Given a TV is running and reachable on the local network

  Scenario: Home shows not-paired status when no TV is paired
    Given the phone has no stored pairing
    When the phone app launches
    Then the home screen shows the "not paired" status icon
    And the "Scan TV code" button is visible
    And the dashboard is not shown

  Scenario: Home shows paired status when a TV is paired
    Given the phone is paired with the TV
    When the phone app launches
    Then the home screen shows the "paired" status icon
    And the "Open Dashboard" button is visible

  @real-device
  Scenario: Pairing by scanning the TV QR code with the camera
    Given the phone has no stored pairing
    When the user taps "Scan TV code"
    Then the camera scanner opens
    When the user points the camera at the QR code shown on the TV
    Then the pairing is stored on the phone
    And the scanner closes
    And the home screen shows the "paired" status icon

  @real-device
  Scenario: Scanning an invalid QR code does not pair
    Given the phone has no stored pairing
    And the camera scanner is open
    When the user points the camera at a QR code that is not an Eleen TV code
    Then the pairing is rejected
    And the scanner stays open for another attempt
    And the home screen still shows the "not paired" status icon

  @real-device
  Scenario: Scanning a QR code for an unreachable TV
    Given the phone has no stored pairing
    And the camera scanner is open
    When the user scans a valid Eleen QR code for a TV that is offline
    Then the pairing is not stored
    And the user can retry the scan or enter the manual code

  @real-device
  Scenario: Cancelling the camera scanner changes nothing
    Given the phone has no stored pairing
    And the camera scanner is open
    When the user backs out of the scanner
    Then the home screen shows the "not paired" status icon
    And no pairing is stored

  Scenario: Pairing by entering the manual code
    Given the phone has no stored pairing
    When the user taps "Scan TV code"
    And the user enters the manual code shown on the TV
    Then the pairing is stored on the phone
    And the home screen shows the "paired" status icon

  Scenario: Pairing survives app relaunch
    Given the phone is paired with the TV
    When the phone app is closed and relaunched
    Then the home screen still shows the "paired" status icon
    And the "Open Dashboard" button is visible

  Scenario: Paired status degrades gracefully when the TV is unreachable
    Given the phone is paired with the TV
    And the TV is offline
    When the phone app launches
    Then the home screen still shows the stored pairing
    And the user can re-pair

  Scenario: Open Dashboard shows per-profile remaining time
    Given the phone is paired with the TV
    And the TV has a child profile "Kid" with 15 minutes remaining
    When the user taps "Open Dashboard"
    Then the dashboard shows the profile "Kid"
    And the profile row shows "15:00 left"

  Scenario: The dashboard warns when the TV lacks the overlay permission
    Given the phone is paired with the TV
    And the TV reports its overlay permission as denied
    When the parent opens the dashboard
    Then a warning explains the TV cannot lock other apps
    When the TV reports the permission as granted
    Then the warning disappears
