// The SYSTEM_ALERT_WINDOW ("Display over other apps") permission — the
// linchpin of background enforcement: without it, the reminder toasts, the
// last-minute badge and the Time's-up lock can never render over YouTube or
// any other running app (showOverlay fails silently). The permission is
// granted manually in system settings, so the app must ASK: we check it
// whenever enforcement is active and surface a banner that routes the
// parent to the system grant screen.
//
// Failures are logged, never thrown; injectable seams live on TvHome.

import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Whether the app may show the platform overlay. Defaults to true on any
/// plugin failure (fail open: the overlay calls log their own failures, and
/// a stuck-false banner would be worse than a missing one).
Future<bool> overlaysAllowed() async {
  try {
    return await FlutterOverlayWindow.isPermissionGranted();
  } catch (error) {
    debugPrint('Eleen: overlay permission check failed: $error');
    return true;
  }
}

/// Opens the system "Display over other apps" screen for the user to grant
/// the permission. Returns whether the request flow completed (the grant
/// itself is re-checked on the next app resume).
Future<bool> requestOverlayPermission() async {
  try {
    final granted = await FlutterOverlayWindow.requestPermission();
    return granted ?? false;
  } catch (error) {
    debugPrint('Eleen: overlay permission request failed: $error');
    return false;
  }
}
