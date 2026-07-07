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
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: AppColors.white,
      primaryContainer: colors.primaryContainer,
      onPrimaryContainer: colors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.white,
      error: AppColors.error,
      onError: AppColors.white,
      errorContainer: colors.errorContainer,
      onErrorContainer: colors.onErrorContainer,
      surface: colors.surface,
      onSurface: colors.textPrimary,
      surfaceContainerHighest: colors.surfaceMuted,
      outline: colors.border,
      outlineVariant: colors.divider,
      scrim: colors.scrim,
    );

    final textTheme = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.background,
      canvasColor: colors.background,
      textTheme: textTheme,
      splashColor: AppColors.primary.withValues(alpha: 0.08),
      highlightColor: AppColors.primary.withValues(alpha: 0.04),
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
