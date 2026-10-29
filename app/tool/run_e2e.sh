#!/bin/sh
# Runs the E2E suites with the SYSTEM_ALERT_WINDOW permission granted for the
# whole run. integration_test uninstalls the app at the end, which drops the
# appops grant — and the banner that appears while the permission is denied
# (correct product behavior!) shifts the home layout, breaking unrelated
# assertions. This watcher re-grants every 2 seconds so the permission is in
# place whenever the app is (re)installed mid-run.
#
# Usage (from app/; adb must be on PATH — e.g. PATH="/opt/homebrew/share/\
# android-commandlinetools/platform-tools:$PATH"):
#   tool/run_e2e.sh integration_test/feature_scenarios_test.dart --dart-define=ELEN_FAST=1 --dart-define=ELEEN_FORM=tv -d emulator-5554
#
# With more than one device attached, export ELEEN_ADB_SERIAL=<serial> (or
# set ADB_SERIAL) so the grant lands on the right device.

set -e

(
  SERIAL="${ELEEN_ADB_SERIAL:-${ADB_SERIAL:-}}"
  ADB_CMD="adb"
  if [ -n "$SERIAL" ]; then ADB_CMD="adb -s $SERIAL"; fi
  if ! adb get-state >/dev/null 2>&1; then
    echo "run_e2e.sh: adb not found on PATH — pass the platform-tools dir:" >&2
    echo '  PATH="/opt/homebrew/share/android-commandlinetools/platform-tools:$PATH" tool/run_e2e.sh ...' >&2
    exit 1
  fi
  while :; do
    $ADB_CMD shell appops set com.eleen.eleen SYSTEM_ALERT_WINDOW allow 2>/dev/null || true
    sleep 2
  done
) &
WATCHER=$!
trap 'kill $WATCHER 2>/dev/null || true' EXIT

flutter test "$@"
