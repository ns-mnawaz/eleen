// Platform bridge: bring Eleen to the front over whatever app is running.
//
// Used when the screen-time lock engages while Eleen is backgrounded: the
// child is watching another app (YouTube, Netflix). Bringing Eleen to the
// front shows the in-app lock (full remote support — a SYSTEM_ALERT_WINDOW
// overlay cannot take TV-remote key input, which is why the interactive
// lock is NOT an overlay) and pauses the running app's activity, so its
// playback stops. Eleen holds SYSTEM_ALERT_WINDOW, which exempts it from
// the background-activity-start restrictions that would otherwise block
// this from a background isolate.
//
// Failures are logged, never thrown: on platforms without the channel
// (tests, desktop) everything still works, only without the bring-forward.
// The RESULT is reported so the caller can retry — a bring-forward that
// silently failed must not leave the lock believing Eleen is already in
// front (see TvHome._engageBackgroundLock).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Brings Eleen to the front over the `eleen/platform` method channel
/// (wired in MainActivity). Returns whether the platform call reached the
/// activity: `false` (logged, never thrown) when it failed or the channel is
/// unavailable, so the caller can retry instead of latching "already in
/// front".
Future<bool> bringAppToFront() async {
  try {
    await const MethodChannel('eleen/platform')
        .invokeMethod<void>('bringToFront');
    return true;
  } catch (error) {
    debugPrint('Eleen: bringAppToFront failed: $error');
    return false;
  }
}
