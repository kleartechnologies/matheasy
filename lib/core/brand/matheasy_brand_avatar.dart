import 'package:flutter/widgets.dart';

import 'matheasy_app_icon.dart';

/// The Matheasy brand avatar — the app's on-brand "presence" glyph.
///
/// This is the single identity element that stands in wherever the product
/// used to show a mascot face: assistant chat turns, empty states, loading
/// moments and feature heroes. It is deliberately **not a character** — it is
/// the official brand identity (the white [MatheasyMark] on the Emerald
/// app-icon tile), so the app reads as brand-led, never mascot-led.
///
/// One knob — [size]. The visual is always the brand, so call sites never pick
/// an "expression"; the identity is constant across every surface.
///
/// ```dart
/// const MatheasyBrandAvatar(size: 34);   // chat / inline
/// const MatheasyBrandAvatar(size: 120);  // empty state / hero
/// ```
class MatheasyBrandAvatar extends StatelessWidget {
  const MatheasyBrandAvatar({
    super.key,
    this.size = 96,
    this.semanticLabel = 'Matheasy',
  });

  /// Edge length of the (square) avatar tile in logical pixels.
  final double size;

  /// Accessibility label. Defaults to the brand name.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: MatheasyAppIcon(size: size),
    );
  }
}
