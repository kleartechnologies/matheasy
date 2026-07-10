import 'package:flutter/widgets.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale for Matheasy, based on **Manrope** — the official brand
/// typeface. A geometric sans with open counters and softly rounded terminals:
/// friendly, highly legible, premium.
///
/// Styles here are colorless — color is applied by the [TextTheme] (which
/// adapts to light/dark) or explicitly at the call site. This keeps a single
/// source of truth for size/weight/spacing while letting color follow theme.
///
/// The font is loaded at runtime via `google_fonts`. For fully offline / first
/// launch performance, bundle the Manrope `.ttf` files and register them in
/// `pubspec.yaml` in a later hardening pass.
class AppTypography {
  const AppTypography._();

  static const String fontFamily = 'Manrope';

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double height = 1.3,
    double letterSpacing = 0,
  }) {
    return GoogleFonts.manrope(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  // ---- Display ----
  static TextStyle get displayLarge =>
      _base(size: 40, weight: FontWeight.w800, height: 1.1, letterSpacing: -1);
  static TextStyle get displayMedium => _base(
        size: 34,
        weight: FontWeight.w800,
        height: 1.12,
        letterSpacing: -0.5,
      );
  static TextStyle get displaySmall => _base(
        size: 28,
        weight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.5,
      );

  // ---- Heading ----
  static TextStyle get headingLarge => _base(
        size: 27,
        weight: FontWeight.w800,
        height: 1.15,
        letterSpacing: -0.5,
      );
  static TextStyle get headingMedium =>
      _base(size: 20, weight: FontWeight.w800, height: 1.2);
  static TextStyle get headingSmall =>
      _base(size: 18, weight: FontWeight.w800, height: 1.25);

  // ---- Title ----
  static TextStyle get title => _base(size: 16, weight: FontWeight.w700);

  // ---- Body ----
  static TextStyle get bodyLarge =>
      _base(size: 16, weight: FontWeight.w500, height: 1.5);
  static TextStyle get bodyMedium =>
      _base(size: 14.5, weight: FontWeight.w500, height: 1.5);
  static TextStyle get bodySmall =>
      _base(size: 13, weight: FontWeight.w500, height: 1.45);

  // ---- Caption ----
  static TextStyle get caption => _base(size: 12, weight: FontWeight.w600);

  // ---- Supporting ----
  /// All-caps eyebrow / overline label.
  static TextStyle get label => _base(
        size: 11.5,
        weight: FontWeight.w800,
        height: 1.2,
        letterSpacing: 0.6,
      );

  /// Technical mono label — **JetBrains Mono**, the brand's companion typeface
  /// for eyebrows, technical captions, and numerals. Loaded at runtime via
  /// `google_fonts`. Use uppercase, tracked, on brand/technical surfaces.
  static TextStyle get mono => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 1.4,
      );

  /// Heavier mono eyebrow for section labels.
  static TextStyle get monoLabel => GoogleFonts.jetBrainsMono(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 1.8,
      );

  /// Text inside buttons.
  static TextStyle get button =>
      _base(size: 16, weight: FontWeight.w800, height: 1.1);

  /// Emphasized numeric / equation style (e.g. answers, XP counters).
  static TextStyle get numeric =>
      _base(size: 34, weight: FontWeight.w800, height: 1.1, letterSpacing: -0.5);
}
