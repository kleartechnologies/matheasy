import 'package:flutter/animation.dart';

/// Motion duration tokens. Every animation in the app must reference one of
/// these — no hardcoded `Duration`s in widgets.
class AppDurations {
  const AppDurations._();

  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration verySlow = Duration(milliseconds: 800);

  // ---- Semantic durations ----
  /// Press / tap scale feedback.
  static const Duration press = Duration(milliseconds: 120);

  /// Route transitions.
  static const Duration page = Duration(milliseconds: 300);

  /// Ambient mascot "floaty" bob loop.
  static const Duration floaty = Duration(seconds: 4);

  /// Sparkle / celebratory accent loop.
  static const Duration sparkle = Duration(milliseconds: 2400);

  /// Typing indicator dot cycle.
  static const Duration typing = Duration(milliseconds: 1200);

  /// Auto-advance interval for the Play Solution walkthrough.
  static const Duration walkthroughStep = Duration(milliseconds: 2600);
}

/// Easing curve tokens paired with [AppDurations].
class AppCurves {
  const AppCurves._();

  /// Default easing for entrances and standard transitions.
  static const Curve standard = Curves.easeOutCubic;

  /// Emphasized easing for hero / expressive motion.
  static const Curve emphasized = Curves.easeOutBack;

  /// For elements leaving the screen.
  static const Curve exit = Curves.easeInCubic;

  /// Smooth symmetric easing for looping ambient motion.
  static const Curve ambient = Curves.easeInOut;
}
