import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-dependent semantic colors delivered as a [ThemeExtension] so every
/// surface/text/container token flips correctly between light and dark.
///
/// Access via `context.colors` (see `context_extensions.dart`).
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceGlass,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInverse,
    required this.border,
    required this.divider,
    required this.scrim,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.streakContainer,
    required this.onStreakContainer,
    required this.xpContainer,
    required this.onXpContainer,
    required this.tabBar,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceGlass;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textInverse;

  final Color border;
  final Color divider;
  final Color scrim;

  final Color primaryContainer;
  final Color onPrimaryContainer;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color errorContainer;
  final Color onErrorContainer;
  final Color streakContainer;
  final Color onStreakContainer;
  final Color xpContainer;
  final Color onXpContainer;

  final Color tabBar;

  static const AppSemanticColors light = AppSemanticColors(
    background: Color(0xFFF4F6F5), // brand page background
    surface: AppColors.white,
    surfaceMuted: Color(0xFFEEF2F0),
    surfaceGlass: Color(0xE6FFFFFF),
    textPrimary: AppColors.ink, // brand ink #0F172A
    textSecondary: Color(0xFF5A6579), // brand body text
    textTertiary: Color(0xFF64748B), // brand micro-label grey — AA-legible on white
    textInverse: AppColors.white,
    border: Color(0xFFE5EAE7), // brand card border
    divider: Color(0xFFEEF1EE),
    scrim: Color(0x8C0F172A),
    primaryContainer: AppColors.emerald50, // Emerald 50 (brand ramp)
    onPrimaryContainer: AppColors.primaryDeep,
    successContainer: Color(0xFFE6F8EC),
    onSuccessContainer: AppColors.successDeep,
    warningContainer: Color(0xFFFFF1E9),
    onWarningContainer: AppColors.warningDeep,
    errorContainer: Color(0xFFFDECEC),
    onErrorContainer: AppColors.errorDeep,
    streakContainer: Color(0xFFFFEEE6),
    onStreakContainer: Color(0xFF9A3412), // deep orange — AA on the peach container
    xpContainer: Color(0xFFFFF6DC),
    onXpContainer: Color(0xFF7A5300), // deep gold — AA on the pale-gold container
    tabBar: Color(0xD1FFFFFF),
  );

  static const AppSemanticColors dark = AppSemanticColors(
    background: AppColors.inkDeep, // brand deep ink #0B1220
    surface: Color(0xFF141C2B),
    surfaceMuted: Color(0xFF1B2333),
    surfaceGlass: Color(0x26FFFFFF),
    textPrimary: Color(0xFFF1F6F4),
    textSecondary: Color(0xFFA2ADC8),
    textTertiary: Color(0xFF6E7999),
    textInverse: AppColors.inkDeep,
    border: Color(0xFF263141),
    divider: Color(0xFF1E2836),
    scrim: Color(0xB3060912),
    primaryContainer: Color(0xFF0C3D2E), // deep emerald
    onPrimaryContainer: AppColors.emerald300, // Emerald 300 (brand ramp)
    successContainer: Color(0xFF14301F),
    onSuccessContainer: Color(0xFF6BE39A),
    warningContainer: Color(0xFF3A2417),
    onWarningContainer: Color(0xFFFFB088),
    errorContainer: Color(0xFF3A1A18),
    onErrorContainer: Color(0xFFFF9A90),
    streakContainer: Color(0xFF3A241C),
    onStreakContainer: Color(0xFFFFB088), // light orange on the dark streak container
    xpContainer: Color(0xFF352C12),
    onXpContainer: Color(0xFFFFD54A), // gold on the dark xp container
    tabBar: Color(0xD1141C2B),
  );

  @override
  AppSemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceGlass,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInverse,
    Color? border,
    Color? divider,
    Color? scrim,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? errorContainer,
    Color? onErrorContainer,
    Color? streakContainer,
    Color? onStreakContainer,
    Color? xpContainer,
    Color? onXpContainer,
    Color? tabBar,
  }) {
    return AppSemanticColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInverse: textInverse ?? this.textInverse,
      border: border ?? this.border,
      divider: divider ?? this.divider,
      scrim: scrim ?? this.scrim,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      errorContainer: errorContainer ?? this.errorContainer,
      onErrorContainer: onErrorContainer ?? this.onErrorContainer,
      streakContainer: streakContainer ?? this.streakContainer,
      onStreakContainer: onStreakContainer ?? this.onStreakContainer,
      xpContainer: xpContainer ?? this.xpContainer,
      onXpContainer: onXpContainer ?? this.onXpContainer,
      tabBar: tabBar ?? this.tabBar,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textInverse: Color.lerp(textInverse, other.textInverse, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer:
          Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      errorContainer: Color.lerp(errorContainer, other.errorContainer, t)!,
      onErrorContainer:
          Color.lerp(onErrorContainer, other.onErrorContainer, t)!,
      streakContainer: Color.lerp(streakContainer, other.streakContainer, t)!,
      onStreakContainer:
          Color.lerp(onStreakContainer, other.onStreakContainer, t)!,
      xpContainer: Color.lerp(xpContainer, other.xpContainer, t)!,
      onXpContainer: Color.lerp(onXpContainer, other.onXpContainer, t)!,
      tabBar: Color.lerp(tabBar, other.tabBar, t)!,
    );
  }
}
