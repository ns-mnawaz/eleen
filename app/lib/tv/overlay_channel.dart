// The overlay channel for the display-only background surfaces.
//
// The SYSTEM_ALERT_WINDOW overlay runs in its own Flutter engine (entrypoint
// `overlayMain` in main.dart) with no database access. Its ONLY job is
// display: the reminder toast pill and the live last-minute countdown badge
// over whatever app is running, pushed one-way from the main isolate over
// flutter_overlay_window's messenger — the `x-slayer/overlay_messenger`
// BasicMessageChannel the plugin forwards bidirectionally between the two
// engines. We register on that channel directly ([OverlayMessenger]) rather
// than through the plugin's `overlayListener` getter, whose private
// single-subscription stream breaks on a second listener.
//
// The INTERACTIVE lock is deliberately NOT an overlay: a platform overlay
// window cannot take TV-remote key input on this platform, so when the lock
// engages while backgrounded the main isolate brings the Eleen activity to
// the front instead (see tv_home + platform_launcher).
//
// Wire format (JSON, main -> overlay, one-way):
//
//   {'type': 'toast', 'message': String}
//   {'type': 'lastMinute', 'seconds': int}   (0 ends it)

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// Direct access to the plugin's overlay messenger channel.
///
/// The plugin's own `overlayListener` getter exposes the stream through a
/// private single-subscription controller, which breaks the moment anything
/// listens twice (a TvHome remount in tests or in production). We register
/// on the same channel ourselves instead: one handler per isolate, a
/// broadcast stream for any number of listeners.
class OverlayMessenger {
  OverlayMessenger._();

  static const BasicMessageChannel<Object?> _channel = BasicMessageChannel(
    'x-slayer/overlay_messenger',
    JSONMessageCodec(),
  );

  static StreamController<Object?>? _controller;
  static bool _registered = false;

  /// Messages received from the other engine (main ↔ overlay isolate).
  /// Idempotent; broadcast so re-mounts can re-subscribe.
  static Stream<Object?> incoming() {
    final existing = _controller;
    if (existing != null) return existing.stream;
    final controller = StreamController<Object?>.broadcast();
    _controller = controller;
    if (!_registered) {
      _registered = true;
      _channel.setMessageHandler((message) async {
        controller.add(message);
        return message;
      });
    }
    return controller.stream;
  }

  /// Sends a message to the other engine.
  static Future<void> send(Object? message) => _channel.send(message);
}

/// Shows the platform overlay in display-only mode: fully transparent and
/// click-through, so whatever app is running (YouTube, ...) stays usable
/// while a reminder toast or the last-minute badge renders on top. The
/// engine (BackgroundReminderOverlay) renders only those pills.
Future<bool> showToastOverlay() async {
  try {
    await FlutterOverlayWindow.showOverlay(
      height: WindowSize.fullCover,
      width: WindowSize.matchParent,
      flag: OverlayFlag.clickThrough,
      overlayTitle: 'Eleen',
      overlayContent: 'Screen time reminder',
    );
    return true;
  } catch (error) {
    debugPrint('Eleen: background toast overlay failed: $error');
    return false;
  }
}

/// Hides the platform overlay (the toasts/badge display).
Future<void> hideToastOverlay() async {
  try {
    await FlutterOverlayWindow.closeOverlay();
  } catch (error) {
    debugPrint('Eleen: hiding the toast overlay failed: $error');
  }
}

/// Outcome of one PIN-entry check (used by the in-app lock overlay).
///
/// - [PinCheck.incomplete]: entry shorter than the PIN — keep entering, no
///   correctness signal yet.
/// - accepted: the entry matched; reveal the chooser.
/// - complete but not accepted: a full-length wrong attempt — show the
///   error.
class PinCheck {
  const PinCheck({required this.accepted, required this.complete});

  const PinCheck.accepted()
      : accepted = true,
        complete = true;

  const PinCheck.incomplete()
      : accepted = false,
        complete = false;

  const PinCheck.wrong()
      : accepted = false,
        complete = true;

  final bool accepted;

  /// Whether the entry was evaluated at all (false = still entering).
  final bool complete;
}

/// Verifies a complete PIN entry against the stored parent PIN. The lock
/// overlay consults this once per digit; a verifier that has its own notion
/// of entry length reports [PinCheck.incomplete] until the attempt is
/// complete (one full-match check per attempt — no per-press correctness
/// feedback a methodical child could use to recover the PIN digit by digit).
typedef PinVerifier = Future<PinCheck> Function(String entry);

/// Overlay-isolate side of the one-way display protocol: parses pushes from
/// the main isolate.
class OverlayChannelClient {
  OverlayChannelClient({
    Stream<Object?>? messages,
  }) : _messages = messages ?? OverlayMessenger.incoming();

  /// The messenger stream (injectable for tests).
  final Stream<Object?> _messages;

  StreamSubscription<Object?>? _sub;
  bool _listening = false;

  final StreamController<String> _toastPushes =
      StreamController<String>.broadcast();

  final StreamController<int> _lastMinutePushes =
      StreamController<int>.broadcast();

  /// Toast messages pushed by the main isolate (`{'type': 'toast',
  /// 'message': ...}`).
  Stream<String> get toastPushes => _toastPushes.stream;

  /// Live last-minute countdown seconds pushed by the main isolate
  /// (`{'type': 'lastMinute', 'seconds': n}`, per second; 0 ends it).
  Stream<int> get lastMinutePushes => _lastMinutePushes.stream;

  /// Starts listening for pushes. Idempotent.
  void listen() {
    if (_listening) return;
    _listening = true;
    _sub = _messages.listen((message) {
      if (message is! Map) return;
      if (message['type'] == 'toast' && message['message'] is String) {
        _toastPushes.add(message['message'] as String);
        return;
      }
      if (message['type'] == 'lastMinute' && message['seconds'] is int) {
        _lastMinutePushes.add(message['seconds'] as int);
        return;
      }
    });
  }

  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    _listening = false;
    unawaited(_toastPushes.close());
    unawaited(_lastMinutePushes.close());
  }
}
