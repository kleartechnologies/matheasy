import 'package:flutter/widgets.dart';

/// Elevation tokens as ready-made [BoxShadow] lists.
///
/// Matheasy uses a signature emerald-tinted elevation in light mode; dark mode
/// falls back to soft black shadows so cards stay legible on dark surfaces.
/// Prefer reading these through the theme-aware `context.elevation`
/// ([AppElevation]) rather than referencing the light/dark lists directly.
class AppShadows {
  const AppShadows._();

  // ---- Light (brand-emerald-tinted) — rgba(16,185,129,a) ----
  static const List<BoxShadow> cardLight = [
    BoxShadow(
      color: Color(0x1410B981), // rgba(16,185,129,0.08)
      blurRadius: 26,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> raisedLight = [
    BoxShadow(
      color: Color(0x2410B981), // rgba(16,185,129,0.14)
      blurRadius: 30,
      offset: Offset(0, 14),
    ),
  ];

  static const List<BoxShadow> floatingLight = [
    BoxShadow(
      color: Color(0x5910B981), // rgba(16,185,129,0.35)
      blurRadius: 40,
      offset: Offset(0, 18),
    ),
  ];

  static const List<BoxShadow> buttonLight = [
    BoxShadow(
      color: Color(0x5910B981),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];

  // ---- Dark (soft black) ----
  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x66000000),
      blurRadius: 20,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> raisedDark = [
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 30,
      offset: Offset(0, 16),
    ),
  ];

  static const List<BoxShadow> floatingDark = [
    BoxShadow(
      color: Color(0x99000000),
      blurRadius: 40,
      offset: Offset(0, 20),
    ),
  ];

  static const List<BoxShadow> buttonDark = [
    BoxShadow(
      color: Color(0x80000000),
      blurRadius: 24,
      offset: Offset(0, 12),
    ),
  ];
}
