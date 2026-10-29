// The lock screen's background slideshow: procedurally generated gradient
// scenes, drawn in-app (no assets, no internet — the APK stays tiny).
//
// A [LockSlideshow] fills its parent and slowly rotates through a handful of
// muted gradient scenes with a cross-fade (~8s per scene). It never renders
// text or takes pointer events; the lock screen paints a scrim above it so
// the headline, PIN pad and chooser stay fully readable.

import 'dart:async';

import 'package:flutter/material.dart';

/// Slow-rotating generated gradient scenes for the lock screen.
class LockSlideshow extends StatefulWidget {
  const LockSlideshow({
    super.key,
    this.interval = const Duration(seconds: 8),
    this.fade = const Duration(milliseconds: 1500),
  });

  /// Time one scene stays fully visible before the cross-fade starts.
  final Duration interval;

  /// Cross-fade duration between scenes.
  final Duration fade;

  @override
  State<LockSlideshow> createState() => _LockSlideshowState();
}

class _LockSlideshowState extends State<LockSlideshow> {
  static const int _sceneCount = 5;

  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() => _index = (_index + 1) % _sceneCount);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keyed per scene so [AnimatedSwitcher] cross-fades the outgoing and
    // incoming scenes over each other.
    return AnimatedSwitcher(
      duration: widget.fade,
      child: _Scene(
        key: Key('lock-scene-$_index'),
        index: _index,
      ),
    );
  }
}

/// One generated scene: a full-bleed linear gradient plus a few soft
/// procedural circles derived from the scene index (variety without assets).
class _Scene extends StatelessWidget {
  const _Scene({super.key, required this.index});

  final int index;

  static const List<List<Color>> _palettes = [
    [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    [Color(0xFF141850), Color(0xFF27346B), Color(0xFF3E5C9A)],
    [Color(0xFF0B3C49), Color(0xFF16525C), Color(0xFF1F6F52)],
    [Color(0xFF241B3A), Color(0xFF3A2A5C), Color(0xFF4C3A78)],
    [Color(0xFF12222E), Color(0xFF1F3A4D), Color(0xFF2A5566)],
  ];

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[index % _palettes.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: CustomPaint(
        painter: _ScenePainter(index: index),
        size: Size.infinite,
      ),
    );
  }
}

/// Soft translucent circles laid out from the scene index — the procedural
/// variation between scenes (deterministic, so tests are stable).
class _ScenePainter extends CustomPainter {
  const _ScenePainter({required this.index});

  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = index;
    for (var i = 0; i < 3; i++) {
      final wobble = ((rng * (i + 3) * 37) % 100) / 100;
      final center = Offset(
        size.width * (0.2 + 0.3 * i + 0.1 * wobble),
        size.height * (0.25 + 0.2 * ((rng + i) % 3) / 2 + 0.1 * wobble),
      );
      final radius = size.shortestSide * (0.25 + 0.1 * wobble);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: 0.03 + 0.02 * wobble)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.index != index;
}
