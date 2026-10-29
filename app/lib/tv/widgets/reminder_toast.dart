// Reminder toast: a SnackBar-style overlay announcing a crossed reminder
// threshold ("10 minutes left"). The countdown screen decides when it is
// visible (shown ~5 seconds, once per threshold); this widget is purely
// presentational.

import 'package:flutter/material.dart';

import '../tv_theme.dart';

/// Transient overlay message for a reminder threshold.
class ReminderToast extends StatelessWidget {
  const ReminderToast({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    // All sizes proportional to the screen, never fixed pixels.
    final size = MediaQuery.sizeOf(context);
    return Container(
      key: const Key('reminder-toast'),
      padding: EdgeInsets.symmetric(
        horizontal: size.width * 0.02,
        vertical: size.height * 0.015,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.inverseSurface,
        borderRadius: BorderRadius.circular(size.width * 0.01),
        boxShadow: const [BoxShadow(blurRadius: 12, color: Colors.black26)],
      ),
      child: Text(
        message,
        // fontSize scales with the text scaler from MediaQuery automatically.
        style: TextStyle(
          color: Theme.of(context).colorScheme.onInverseSurface,
          fontSize: TvType.body(size.width),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
