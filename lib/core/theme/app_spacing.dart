/// Spacing scale built on a 4-point grid. Use these tokens for every gap,
/// padding and margin — no raw numbers in widgets.
class AppSpacing {
  const AppSpacing._();

  static const double none = 0;
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;

  // ---- Semantic spacing ----
  /// Default horizontal screen padding.
  static const double screenH = 20;

  /// Space between major sections on a screen.
  static const double section = 26;

  /// Inner padding used by [AppCard] and most surfaces.
  static const double card = 16;

  /// Bottom padding to clear the floating tab bar on scrollable screens.
  static const double tabClearance = 120;

  /// Top padding to clear the status bar area on custom headers.
  static const double statusBar = 58;
}
