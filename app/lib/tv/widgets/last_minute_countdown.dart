// Per-second countdown for the final session-minute, pinned to the top-right
// of the TV countdown screen.

import 'package:flutter/material.dart';

import '../tv_theme.dart';

/// Formats session seconds as `m:ss` — minutes unpadded, seconds
/// zero-padded: 900 -> '15:00', 605 -> '10:05', 59 -> '0:59'.
String formatSessionSeconds(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The remaining time once the session has entered its last minute.
/// Rebuilt per second by the countdown screen, which hides it again at 0.
class LastMinuteCountdown extends StatelessWidget {
  const LastMinuteCountdown({super.key, required this.secondsRemaining});

  final int secondsRemaining;

  @override
  Widget build(BuildContext context) {
    // All sizes proportional to the screen, never fixed pixels.
    final size = MediaQuery.sizeOf(context);
    return Container(
      key: const Key('last-minute-countdown'),
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.015,
        vertical: size.height * 0.008,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(size.width * 0.01),
      ),
      child: Text(
        formatSessionSeconds(secondsRemaining),
        // fontSize scales with the text scaler from MediaQuery automatically.
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontSize: TvType.entry(size.width),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
