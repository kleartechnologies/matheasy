import 'package:flutter/widgets.dart';

/// Elevation tokens as ready-made [BoxShadow] lists.
///
/// Restrained, neutral shadows — no emerald glow / bloom. Elevation is carried
/// by surface colour, a hairline border and spacing; shadows are a soft, subtle
/// hint only. Prefer reading these through `context.elevation` ([AppElevation]).
class AppShadows {
  const AppShadows._();

  // ---- Light (soft neutral) — rgba(15,23,42,a) ----
  static const List<BoxShadow> cardLight = [
    BoxShadow(
      color: Color(0x0D0F172A), // rgba(15,23,42,0.05)
      blurRadius: 18,
      offset: Offset(0, 6),
    ),
  ];

  static const List<BoxShadow> raisedLight = [
    BoxShadow(
      color: Color(0x140F172A), // rgba(15,23,42,0.08)
      blurRadius: 24,
      offset: Offset(0, 10),
    ),
  ];

  static const List<BoxShadow> floatingLight = [
    BoxShadow(
      color: Color(0x1F0F172A), // rgba(15,23,42,0.12)
      blurRadius: 30,
      offset: Offset(0, 14),
    ),
  ];

  static const List<BoxShadow> buttonLight = [
    BoxShadow(
      color: Color(0x140F172A),
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
