import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Theme-dependent semantic colors delivered as a [ThemeExtension] so every
/// surface/text/container token flips correctly between light and dark.
///
/// Access via `context.colors` (see `context_extensions.dart`).
///
/// ## Derived from the logo
///
/// The neutrals here are not grey — they are the logo's own hue (≈155) held at
/// a low saturation, so surfaces and text sit in the same family as the emerald
/// instead of fighting it with a cold blue-slate. Dark mode is the logo's
/// outline tone [AppColors.emerald900] carried down past it: `#081410` /
/// `#0E1F18` / `#14291F`.
///
/// Every text-on-surface pair in this file clears WCAG AA (4.5:1) in both
/// themes. `test/core/theme/brand_contrast_test.dart` enforces it.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.background,
    required this.surface,
    required this.card,
    required this.surfaceMuted,
    required this.surfaceGlass,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
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
    required this.errorText,
    required this.infoContainer,
    required this.onInfoContainer,
    required this.streakContainer,
    required this.onStreakContainer,
    required this.xpContainer,
    required this.onXpContainer,
    required this.tabBar,
    required this.tabBarGlass,
  });

  /// The page backdrop.
  final Color background;

  /// A raised surface (sheets, bars).
  final Color surface;

  /// A content card. Same value as [surface] today, but named separately so
  /// cards can gain their own elevation tint without touching every sheet.
  final Color card;

  /// A recessed / muted surface (input fills, tracks, inactive chips).
  final Color surfaceMuted;

  final Color surfaceGlass;

  /// Body and heading text — the brand ink. 17.21:1 on white.
  final Color textPrimary;

  /// Supporting text. 6.19:1 on white / 5.74:1 on the page background.
  final Color textSecondary;

  /// Micro-labels and metadata — the quietest text that is still AA on every
  /// surface it can land on, [surfaceMuted] included.
  final Color textMuted;

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

  /// Error as **text/icon on a page surface** — Material paints
  /// `InputDecorator`'s error label and focused-error border with
  /// `colorScheme.error`, so that role has to flip with the theme.
  /// [AppColors.error] is 5.96:1 on white but only 2.87:1 on the dark surface;
  /// dark mode steps up to the light red instead.
  final Color errorText;

  final Color infoContainer;
  final Color onInfoContainer;
  final Color streakContainer;
  final Color onStreakContainer;
  final Color xpContainer;
  final Color onXpContainer;

  final Color tabBar;

  /// Translucent overlay painted over the tab bar's [BackdropFilter] blur.
  /// Deliberately more transparent than [tabBar] so scrollable content genuinely
  /// blurs through the bar; [tabBar] stays for the opaque badge ring that masks
  /// the badge from the icon beneath it.
  final Color tabBarGlass;

  static const AppSemanticColors light = AppSemanticColors(
    background: Color(0xFFF4F7F5), // brand hue at 97% L — warm, not blue-grey
    surface: AppColors.white,
    card: AppColors.white,
    surfaceMuted: Color(0xFFEBF0EE),
    surfaceGlass: Color(0xE6FFFFFF),
    textPrimary: AppColors.ink, // #0A1F16 — 17.21:1 on white
    textSecondary: Color(0xFF53655E), // 6.19:1 on white
    // Sized to clear AA on the *muted* surface too (4.63:1), which is the
    // darkest thing it ever lands on — not just on white.
    textMuted: Color(0xFF5D6F68), // 5.33 on white / 4.94 on bg / 4.63 on muted
    textInverse: AppColors.white,
    border: Color(0xFFDFE7E4),
    divider: Color(0xFFEEF2F0),
    scrim: Color(0x8C0A1F16),
    primaryContainer: AppColors.emerald50,
    onPrimaryContainer: AppColors.primaryDeep, // 11.08:1 ✓
    successContainer: AppColors.emerald50,
    onSuccessContainer: AppColors.successDeep,
    warningContainer: Color(0xFFFDF0E4),
    onWarningContainer: AppColors.warningDeep,
    errorContainer: Color(0xFFFCEAE8),
    onErrorContainer: AppColors.errorDeep,
    errorText: AppColors.error, // 5.96:1 on white ✓
    infoContainer: Color(0xFFE7F1FA),
    onInfoContainer: AppColors.infoDeep,
    streakContainer: Color(0xFFFDF0E4),
    onStreakContainer: AppColors.warningDeep,
    xpContainer: Color(0xFFFFF6DC),
    onXpContainer: Color(0xFF6B4A00), // deep gold — AA on the pale-gold container
    tabBar: Color(0xD1FFFFFF),
    tabBarGlass: Color(0xC2FFFFFF), // frosted white — content blurs through
  );

  static const AppSemanticColors dark = AppSemanticColors(
    background: Color(0xFF081410), // the logo's outline tone, carried down
    surface: Color(0xFF0E1F18),
    card: Color(0xFF0E1F18),
    surfaceMuted: Color(0xFF14291F),
    surfaceGlass: Color(0x1FFFFFFF),
    textPrimary: Color(0xFFE8F2EC), // 14.94:1 on surface
    textSecondary: Color(0xFFAFC0B9), // 9.01:1 on surface
    textMuted: Color(0xFF8A9E96), // 6.04:1 on surface
    textInverse: AppColors.inkDeep,
    border: Color(0x14FFFFFF), // white 8% — a hairline, not a slate rule
    divider: Color(0x0AFFFFFF), // white 4%
    scrim: Color(0xB3030A07),
    primaryContainer: Color(0xFF0A3323),
    onPrimaryContainer: AppColors.emerald300, // 9.73:1 ✓
    successContainer: Color(0xFF0A3323),
    onSuccessContainer: AppColors.emerald300,
    warningContainer: Color(0xFF33200D),
    onWarningContainer: Color(0xFFF5B876),
    errorContainer: Color(0xFF331512),
    onErrorContainer: Color(0xFFF29289),
    errorText: Color(0xFFF29289), // 7.53:1 on the dark surface ✓
    infoContainer: Color(0xFF0C2438),
    onInfoContainer: Color(0xFF7FBBEA),
    streakContainer: Color(0xFF33200D),
    onStreakContainer: Color(0xFFF5B876),
    xpContainer: Color(0xFF2E2610),
    onXpContainer: AppColors.gold,
    tabBar: Color(0xE60E1F18),
    tabBarGlass: Color(0x8C0A1912), // deep emerald-ink @ 55% — frosted glass
  );

  @override
  AppSemanticColors copyWith({
    Color? background,
    Color? surface,
    Color? card,
    Color? surfaceMuted,
    Color? surfaceGlass,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
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
    Color? errorText,
    Color? infoContainer,
    Color? onInfoContainer,
    Color? streakContainer,
    Color? onStreakContainer,
    Color? xpContainer,
    Color? onXpContainer,
    Color? tabBar,
    Color? tabBarGlass,
  }) {
    return AppSemanticColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      card: card ?? this.card,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceGlass: surfaceGlass ?? this.surfaceGlass,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
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
      errorText: errorText ?? this.errorText,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
      streakContainer: streakContainer ?? this.streakContainer,
      onStreakContainer: onStreakContainer ?? this.onStreakContainer,
      xpContainer: xpContainer ?? this.xpContainer,
      onXpContainer: onXpContainer ?? this.onXpContainer,
      tabBar: tabBar ?? this.tabBar,
      tabBarGlass: tabBarGlass ?? this.tabBarGlass,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceGlass: Color.lerp(surfaceGlass, other.surfaceGlass, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
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
      errorText: Color.lerp(errorText, other.errorText, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
      streakContainer: Color.lerp(streakContainer, other.streakContainer, t)!,
      onStreakContainer:
          Color.lerp(onStreakContainer, other.onStreakContainer, t)!,
      xpContainer: Color.lerp(xpContainer, other.xpContainer, t)!,
      onXpContainer: Color.lerp(onXpContainer, other.onXpContainer, t)!,
      tabBar: Color.lerp(tabBar, other.tabBar, t)!,
      tabBarGlass: Color.lerp(tabBarGlass, other.tabBarGlass, t)!,
    );
  }
}
