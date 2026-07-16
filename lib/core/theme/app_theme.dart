import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_durations.dart';
import 'app_elevation.dart';
import 'app_radius.dart';
import 'app_semantic_colors.dart';
import 'app_typography.dart';

/// Assembles production-ready light and dark [ThemeData] for Matheasy.
///
/// The heavy lifting for brand tokens lives in the [AppSemanticColors] and
/// [AppElevation] theme extensions; this file wires them into a Material theme
/// plus the [TextTheme] and common component themes.
class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(
        brightness: Brightness.light,
        colors: AppSemanticColors.light,
        elevation: AppElevation.light,
      );

  static ThemeData get dark => _build(
        brightness: Brightness.dark,
        colors: AppSemanticColors.dark,
        elevation: AppElevation.dark,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppSemanticColors colors,
    required AppElevation elevation,
  }) {
    final isDark = brightness == Brightness.dark;

    // Material's own widgets reach far past the roles the brand names:
    // InputDecorator hints and ListTile subtitles read `onSurfaceVariant`,
    // Chip/SegmentedButton read `secondaryContainer`, Switch reads the surface
    // container tiers. Any role left to the seed comes back an off-brand tonal
    // green that no token controls, so every role a shipped widget can reach is
    // pinned below.
    final scheme = ColorScheme.fromSeed(
      // Seed from the interactive tone, not the identity tone: the roles derived
      // from the seed land *behind controls*, so they must descend from the
      // emerald that is safe under white content.
      seedColor: AppColors.primaryAction,
      brightness: brightness,
    ).copyWith(
      // Material fills buttons and FABs with primary + onPrimary, so primary
      // must be the action emerald (white 4.78:1 ✓ AA) and never the identity
      // emerald (2.97:1).
      primary: AppColors.primaryAction,
      onPrimary: AppColors.white,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: colors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.white,
      // [secondary] stays the indigo categorical accent, but the *container*
      // role is what M3 paints selected chips and nav indicators with — those
      // are brand states, so they take the emerald container. No indigo
      // container token exists, and inventing one would add a second selected
      // colour to the system.
      secondaryContainer: colors.primaryContainer,
      onSecondaryContainer: colors.onPrimaryContainer,
      // Tertiary = the categorical accent [secondary] does not already spell.
      tertiary: AppColors.accentCoral, // white 5.18:1 ✓ AA
      onTertiary: AppColors.white,
      // No coral container token exists; the warm container is its nearest
      // tonal sibling (same orange family, hue 17 vs 28) and clears AA in both
      // themes.
      tertiaryContainer: colors.warningContainer,
      onTertiaryContainer: colors.onWarningContainer,
      // Material paints InputDecorator error text + the focused-error border
      // with this role, so it must flip with the theme: AppColors.error is
      // 2.87:1 on the dark surface. onError pairs with it as a FILL.
      error: colors.errorText,
      onError: isDark ? AppColors.ink : AppColors.white,
      errorContainer: colors.errorContainer,
      onErrorContainer: colors.onErrorContainer,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      onSurfaceVariant: colors.textSecondary,
      // The palette defines three surface tiers, not five: the upper containers
      // collapse onto [surfaceMuted] rather than fall back to seed greens. The
      // ladder inverts with brightness — lowest is the brightest in light and
      // the deepest in dark.
      surfaceBright: isDark ? colors.surfaceMuted : colors.surface,
      surfaceDim: isDark ? colors.background : colors.surfaceMuted,
      surfaceContainerLowest: isDark ? colors.background : colors.surface,
      surfaceContainerLow: isDark ? colors.surface : colors.background,
      surfaceContainer: colors.surfaceMuted,
      surfaceContainerHigh: colors.surfaceMuted,
      surfaceContainerHighest: colors.surfaceMuted,
      outline: colors.border,
      outlineVariant: colors.divider,
      // Shadows stay neutral ink — no emerald bloom. See [AppShadows].
      shadow: AppColors.ink,
      scrim: colors.scrim,
      // The inverted pair snackbars and tooltips sit on — the same two tokens
      // the SnackBar theme below already pairs by hand.
      inverseSurface: colors.textPrimary,
      onInverseSurface: colors.textInverse,
      // The emerald that survives *on* that inverted surface, so it flips with
      // the theme: 10.19:1 on light's inverse, 5.96:1 on dark's.
      inversePrimary: isDark ? AppColors.primaryDark : AppColors.primaryLight,
      // M3 tints elevated surfaces with this. The brand carries elevation with
      // surface colour, a hairline border and a neutral shadow, and every
      // component theme below already zeroes surfaceTintColor one by one —
      // transparent makes that the default instead of the exception.
      surfaceTint: Colors.transparent,
    );

    final textTheme = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme,
      // Ripples belong to the interactive emerald, not the identity one.
      splashColor: AppColors.primaryAction.withValues(alpha: 0.08),
      highlightColor: AppColors.primaryAction.withValues(alpha: 0.04),
      extensions: <ThemeExtension<dynamic>>[colors, elevation],
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTypography.headingSmall.copyWith(
          color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      iconTheme: IconThemeData(color: colors.textSecondary),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: colors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetRadius),
        showDragHandle: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.modalRadius),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colors.textPrimary,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: colors.textInverse,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.mdRadius),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );
  }

  static TextTheme _textTheme(AppSemanticColors c) {
    final primary = c.textPrimary;
    final secondary = c.textSecondary;
    return TextTheme(
      displayLarge: AppTypography.displayLarge.copyWith(color: primary),
      displayMedium: AppTypography.displayMedium.copyWith(color: primary),
      displaySmall: AppTypography.displaySmall.copyWith(color: primary),
      headlineLarge: AppTypography.headingLarge.copyWith(color: primary),
      headlineMedium: AppTypography.headingMedium.copyWith(color: primary),
      headlineSmall: AppTypography.headingSmall.copyWith(color: primary),
      titleLarge: AppTypography.title.copyWith(color: primary),
      titleMedium: AppTypography.title.copyWith(color: primary),
      titleSmall: AppTypography.caption.copyWith(color: secondary),
      bodyLarge: AppTypography.bodyLarge.copyWith(color: primary),
      bodyMedium: AppTypography.bodyMedium.copyWith(color: primary),
      bodySmall: AppTypography.bodySmall.copyWith(color: secondary),
      labelLarge: AppTypography.button.copyWith(color: primary),
      labelMedium: AppTypography.caption.copyWith(color: secondary),
      labelSmall: AppTypography.label.copyWith(color: secondary),
    );
  }
}

/// Motion defaults exposed on the theme for convenience. Currently these
/// mirror [AppDurations]; kept here so widgets can read a single source.
class AppMotion {
  const AppMotion._();
  static const Duration fast = AppDurations.fast;
  static const Duration medium = AppDurations.medium;
  static const Duration slow = AppDurations.slow;
}
