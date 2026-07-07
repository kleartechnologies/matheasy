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
}
