import 'package:flutter/material.dart';

import '../theme/app_breakpoints.dart';
import '../theme/app_elevation.dart';
import '../theme/app_semantic_colors.dart';

/// Ergonomic accessors on [BuildContext] for theme, semantic colors, elevation,
/// typography and layout metrics. Keeps widget code free of repetitive
/// `Theme.of(context)` boilerplate.
extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get text => Theme.of(this).textTheme;
  ColorScheme get scheme => Theme.of(this).colorScheme;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// Semantic (theme-aware) color tokens. See [AppSemanticColors].
  ///
  /// The fallback follows the ambient brightness: a bare [Theme] (tests, a
  /// widget scoped under `ThemeData.dark()`) must not silently hand back light
  /// surfaces and light-on-light text.
  AppSemanticColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppSemanticColors>() ??
        (theme.brightness == Brightness.dark
            ? AppSemanticColors.dark
            : AppSemanticColors.light);
  }

  /// Theme-aware elevation (shadow) tokens. See [AppElevation].
  AppElevation get elevation {
    final theme = Theme.of(this);
    return theme.extension<AppElevation>() ??
        (theme.brightness == Brightness.dark
            ? AppElevation.dark
            : AppElevation.light);
  }

  // ---- Layout metrics ----
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
  EdgeInsets get viewInsets => MediaQuery.viewInsetsOf(this);

  bool get isTablet => AppBreakpoints.isTablet(screenWidth);
  bool get isDesktop => AppBreakpoints.isDesktop(screenWidth);
}
