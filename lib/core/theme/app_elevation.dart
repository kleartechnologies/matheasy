import 'package:flutter/material.dart';

import 'app_shadows.dart';

/// Theme-aware elevation delivered as a [ThemeExtension]. Selects the correct
/// (blue-tinted vs. soft-black) shadow set for the active brightness.
///
/// Access via `context.elevation`.
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({
    required this.card,
    required this.raised,
    required this.floating,
    required this.button,
  });

  final List<BoxShadow> card;
  final List<BoxShadow> raised;
  final List<BoxShadow> floating;
  final List<BoxShadow> button;

  static const AppElevation light = AppElevation(
    card: AppShadows.cardLight,
    raised: AppShadows.raisedLight,
    floating: AppShadows.floatingLight,
    button: AppShadows.buttonLight,
  );

  static const AppElevation dark = AppElevation(
    card: AppShadows.cardDark,
    raised: AppShadows.raisedDark,
    floating: AppShadows.floatingDark,
    button: AppShadows.buttonDark,
  );

  @override
  AppElevation copyWith({
    List<BoxShadow>? card,
    List<BoxShadow>? raised,
    List<BoxShadow>? floating,
    List<BoxShadow>? button,
  }) {
    return AppElevation(
      card: card ?? this.card,
      raised: raised ?? this.raised,
      floating: floating ?? this.floating,
      button: button ?? this.button,
    );
  }

  @override
  AppElevation lerp(ThemeExtension<AppElevation>? other, double t) {
    if (other is! AppElevation) return this;
    // Shadows are discrete sets; snap at the midpoint of the theme cross-fade.
    return t < 0.5 ? this : other;
  }
}
