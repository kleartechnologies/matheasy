/// Responsive breakpoint tokens. Matheasy is a phone-first app; these mainly
/// let large-screen layouts (tablet / foldable / desktop preview) center and
/// cap their content width instead of stretching edge to edge.
class AppBreakpoints {
  const AppBreakpoints._();

  static const double mobile = 0;
  static const double tablet = 600;
  static const double desktop = 1024;

  /// Maximum width phone-style content should occupy on wide screens.
  static const double maxContentWidth = 480;

  static bool isTablet(double width) =>
      width >= tablet && width < desktop;

  static bool isDesktop(double width) => width >= desktop;

  static bool isMobile(double width) => width < tablet;
}
