import 'package:flutter/widgets.dart';

/// Elevation tokens as ready-made [BoxShadow] lists.
///
/// Restrained, neutral shadows — no emerald glow / bloom. Elevation is carried
/// by surface colour, a hairline border and spacing; shadows are a soft, subtle
/// hint only. Prefer reading these through `context.elevation` ([AppElevation]).
///
/// Light shadows are `AppColors.ink` (#0A1F16) at a low alpha; dark shadows are
/// soft black. The alpha is baked into the literal because these lists are
/// `const` — `AppColors.ink.withValues()` is not a compile-time constant.
class AppShadows {
  const AppShadows._();

  // ---- Light (soft neutral ink) — rgba(10,31,22,a) ----
  static const List<BoxShadow> cardLight = [
    BoxShadow(
      color: Color(0x0D0A1F16), // ink @ 5%
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> raisedLight = [
    BoxShadow(
      color: Color(0x140A1F16), // ink @ 8%
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> floatingLight = [
    BoxShadow(
      color: Color(0x1F0A1F16), // ink @ 12%
      blurRadius: 30,
      offset: Offset(0, 14),
    ),
  ];

  static const List<BoxShadow> buttonLight = [
    BoxShadow(
      color: Color(0x140A1F16), // ink @ 8%
      blurRadius: 14,
      offset: Offset(0, 6),
    ),
  ];

  // ---- Dark (near-flat soft black) ----
  static const List<BoxShadow> cardDark = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 14,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> raisedDark = [
    BoxShadow(
      color: Color(0x4D000000),
      blurRadius: 20,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> floatingDark = [
    BoxShadow(
      color: Color(0x59000000),
      blurRadius: 26,
      offset: Offset(0, 12),
    ),
  ];

  static const List<BoxShadow> buttonDark = [
    BoxShadow(
      color: Color(0x33000000),
      blurRadius: 14,
      offset: Offset(0, 6),
    ),
  ];
}
