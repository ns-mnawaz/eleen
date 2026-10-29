# Eleen — Google Play Store Listing

Copy-paste material for the Play Console. Assets live in [assets/](assets/).

## App name

**Eleen**

## Short description (80 chars max)

Gentle TV time limits for kids — profiles, PIN-protected extra time, phone remote.

## Full description (4000 chars max)

Eleen helps families manage Android TV time — gently, fairly, and without
subscriptions, accounts, or the internet.

**A profile for every child**
Create a profile per family member with a daily allowance of 15, 30, 45, or
60 minutes. Each child picks their profile when they sit down in front of
the TV.

**Time runs out, screen pauses**
When the allowance is used up, Eleen shows a friendly full-screen message and
locks the TV. No arguments, no nagging — the rules are clear and always the
same.

**Parents are in charge**
More time? Only a parent decides. Enter your 4-digit PIN on the TV remote —
or do it from your phone without leaving the couch.

**Your phone is the remote control**
Pair Eleen on your phone and your TV by scanning one QR code. From your
phone you can see every profile's remaining time live, add extra minutes,
override today's allowance, or pause all TV time instantly with the master
lock.

**Gentle reminders, not surprises**
Kids see a friendly heads-up at 15, 10, and 5 minutes left, and a small
countdown in the corner during the final minute — so the end of TV time
never comes as a shock.

**Private by design**
Eleen works entirely over your home Wi-Fi. No account, no internet, no data
leaves your home, nothing is tracked or collected.

- Free. No ads. No in-app purchases. No subscription.
- Works on Android TV and Android phones.
- Made for families, by a parent.

## Category

Parenting

## Tags / keywords to consider

screen time, parental controls, tv time limit, kids, family, timer

## Data Safety answers

| Question | Answer |
|---|---|
| Does your app collect or share any user data? | **No.** Eleen works entirely on the local network. No data is collected, transmitted off-device, or shared with third parties. |
| Data security section | All sections: **No** (no location, personal info, activity, identifiers, or any other category). |

## Content rating (IARC questionnaire)

| Question | Answer |
|---|---|
| Does the app contain violence, sexual content, profanity, controlled substances, gambling? | No, all categories. |
| User-generated content or social features? | No. |
| Location sharing? | No. |
| Expected rating | Everyone / suitable for all audiences. |

## Privacy policy

`privacy-policy.html` in this directory — host it anywhere public (GitHub
Pages is easiest: enable Pages on the repo, the file becomes
`https://<user>.github.io/<repo>/docs/store/privacy-policy.html`) and paste
the URL into the Play Console.

## Screenshot plan (take on devices or emulators)

Phone (eleen_phone AVD or real phone):
1. Profiles dashboard with 2–3 profiles showing remaining time
2. PIN dialog (add time)
3. Master lock switch on
4. QR scanner/pairing screen

TV (eleen_tv AVD — screenshots via `adb screencap`):
1. Profile picker with avatars
2. Countdown screen with remaining time
3. Reminder toast at 10 minutes
4. Last-minute countdown (top-right badge)
5. Time's-up lock overlay with PIN pad

## Declarations to review in Play Console

- **News apps**: No
- **Ads**: No
- **Target audience**: Families / Parents (general audience; select
  "18+" for the parents-facing controls plus "Designed for Families" only
  if you want to opt in — not required since the app is parent-operated)
- **Access instructions**: If asked, note the app requires pairing with a
  phone on the same Wi-Fi and a parent PIN set during first pairing.
