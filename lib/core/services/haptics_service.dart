import 'package:flutter/services.dart';

/// Thin wrapper over [HapticFeedback] so interaction feedback is consistent and
/// centrally tunable (and easy to mock/disable in tests or settings later).
class HapticsService {
  const HapticsService._();

  static void selection() => HapticFeedback.selectionClick();
  static void light() => HapticFeedback.lightImpact();
  static void medium() => HapticFeedback.mediumImpact();
  static void success() => HapticFeedback.mediumImpact();
  static void warning() => HapticFeedback.heavyImpact();

  // ---- Animated Learning Engine step feedback ----
  /// A step advances (a new beat begins).
  static void step() => HapticFeedback.selectionClick();

  /// Terms merge / a value resolves.
  static void merge() => HapticFeedback.lightImpact();

  /// The final answer is reached (paired with the celebration burst).
  static void celebrate() => HapticFeedback.mediumImpact();
}
