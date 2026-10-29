// Shared TV design tokens (e2e bug report, BUG-9): one palette, one
// proportional type scale and one vertical rhythm, so every TV screen
// (home, picker, form, PIN settings, countdown, lock overlay) reads as the
// same product.
//
// The lock surfaces stay dark (black + white) — that identity is preserved;
// the form/countdown surfaces keep the Material 3 theme defaults and borrow
// only the shared scale helpers. Nothing here introduces fixed pixels: every
// helper is a fraction of a reference width/height, matching the existing
// "sizes are proportional to the screen" rule across the TV widgets.

import 'package:flutter/material.dart';

/// The TV palette: dark lock surfaces, one error tone, one accent.
abstract final class TvColors {
  /// Opaque black behind the lock overlay.
  static const Color background = Color(0xFF000000);

  /// The scrim over the lock slideshow: dark enough for readable white text,
  /// light enough that the scene stays faintly visible.
  static const Color scrim = Color.fromRGBO(0, 0, 0, 0.55);

  /// The modal scrim behind a PIN gate over the picker (== Colors.black87).
  static const Color modalScrim = Color(0xDD000000);

  /// Primary text on dark surfaces.
  static const Color onDark = Color(0xFFFFFFFF);

  /// Secondary / hint text on dark surfaces (== Colors.white70).
  static const Color onDarkMuted = Color(0xB3FFFFFF);

  /// The single TV error tone: readable on both the dark lock surfaces and
  /// the light Material form surfaces (unlike the M3 default, which is too
  /// low-contrast on black).
  static const Color error = Color(0xFFE53935);

  /// The TV accent (Material indigo), matching the app's color seed.
  static const Color accent = Color(0xFF3F51B5);
}

/// Proportional type scale: every size is a fraction of a reference width,
/// so text tracks the screen the same way on every TV surface.
abstract final class TvType {
  /// The lock-overlay headline ("Time's up!").
  static double headline(double width) => width * 0.06;

  /// The big per-second countdown.
  static double countdown(double width) => width * 0.2;

  /// Screen / sheet titles.
  static double title(double width) => width * 0.04;

  /// The PIN-entry bullets and the parent-session banner line.
  static double entry(double width) => width * 0.035;

  /// Primary button and text-field labels.
  static double button(double width) => width * 0.03;

  /// Emphasised form labels.
  static double label(double width) => width * 0.028;

  /// Body copy and hints.
  static double body(double width) => width * 0.025;

  /// Secondary captions.
  static double caption(double width) => width * 0.02;

  /// The smallest supporting line.
  static double small(double width) => width * 0.018;
}

/// Proportional vertical rhythm (fractions of a reference height).
abstract final class TvSpace {
  static double sm(double height) => height * 0.02;
  static double md(double height) => height * 0.03;
  static double lg(double height) => height * 0.04;
}

/// Shared PIN-pad geometry. The pad has four rows (1-2-3 / 4-5-6 / 7-8-9 /
/// 0); the screens cap its height to a fraction of the viewport so the
/// surrounding content (headline, action row) stays on-screen on short 540p
/// TVs, where the accumulated spacers used to push the action row and the
/// '0' row below the fold.
abstract final class TvPinPad {
  /// Rows in the pad.
  static const int rows = 4;

  /// The natural (width-proportional) cell size, used when nothing caps the
  /// pad.
  static double naturalCell(double width) => width * 0.08;

  /// The largest fraction of the viewport height the pad may occupy on the
  /// PIN-settings sheet (which also carries an action row).
  static const double sheetHeightFraction = 0.40;

  /// The largest fraction of the viewport height the pad may occupy on the
  /// lock overlay (which carries a headline + hint).
  static const double overlayHeightFraction = 0.45;
}
