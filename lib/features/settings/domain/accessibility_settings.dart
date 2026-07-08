import 'package:flutter/foundation.dart';

/// Accessibility preferences.
///
/// STAGE 10: infrastructure + persistence. [largerText] and [reducedMotion] are
/// wired through the root `MediaQuery` (text scaling + animation suppression);
/// [highContrast] and [voiceFeedback] are persisted and surfaced in the UI, with
/// their functional wiring reserved for a later hardening pass.
@immutable
class AccessibilitySettings {
  const AccessibilitySettings({
    this.largerText = false,
    this.reducedMotion = false,
    this.highContrast = false,
    this.voiceFeedback = false,
  });

  static const AccessibilitySettings defaults = AccessibilitySettings();

  final bool largerText;
  final bool reducedMotion;
  final bool highContrast;
  final bool voiceFeedback;

  /// The text scale factor applied at the root when [largerText] is enabled.
  double get textScale => largerText ? 1.15 : 1.0;

  AccessibilitySettings copyWith({
    bool? largerText,
    bool? reducedMotion,
    bool? highContrast,
    bool? voiceFeedback,
  }) {
    return AccessibilitySettings(
      largerText: largerText ?? this.largerText,
      reducedMotion: reducedMotion ?? this.reducedMotion,
      highContrast: highContrast ?? this.highContrast,
      voiceFeedback: voiceFeedback ?? this.voiceFeedback,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AccessibilitySettings &&
      other.largerText == largerText &&
      other.reducedMotion == reducedMotion &&
      other.highContrast == highContrast &&
      other.voiceFeedback == voiceFeedback;

  @override
  int get hashCode =>
      Object.hash(largerText, reducedMotion, highContrast, voiceFeedback);
}
