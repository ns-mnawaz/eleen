// The Android foreground service that keeps the app's process alive while
// a child screen-time session runs, so the per-second countdown keeps
// ticking in the background (another app in front) instead of being frozen
// or killed by the OS. The session bills REAL wall-clock time — even if
// the process is suspended anyway, the next tick charges the full elapsed
// gap — the service just makes that gap unlikely and the expiry/overlay
// engage on time.
//
// Failures are logged, never thrown: on platforms without the service
// (tests, desktop) everything still works, only without the guarantee.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Start/stop the session foreground service over the `eleen/session_fg`
/// method channel (wired in MainActivity to SessionForegroundService).
class SessionForegroundService {
  SessionForegroundService._();

  static const MethodChannel _channel = MethodChannel('eleen/session_fg');

  static Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('start');
    } catch (error) {
      debugPrint('Eleen: session foreground service failed to start: '
          '$error');
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error) {
      debugPrint('Eleen: session foreground service failed to stop: '
          '$error');
    }
  }
}
