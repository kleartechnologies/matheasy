import 'package:flutter/widgets.dart';

import 'matheasy_app_icon.dart';

/// The Matheasy brand avatar — the app's on-brand "presence" glyph.
///
/// This is the single identity element that stands in wherever the product
/// used to show a mascot face: assistant chat turns, empty states, loading
/// moments and feature heroes. It is deliberately **not a character** — it is
/// the official brand identity, so the app reads as brand-led, never
/// mascot-led.
///
/// It renders the **official rendered logo artwork** ([kBrandIconAsset] — the
/// white M with the deep-forest outline and long shadow on the flat-emerald
/// field), clipped to the app-icon corner radius. So the in-app presence glyph
/// is now pixel-identical to the shipped launcher icon, not the flat vector
/// [MatheasyAppIcon] (which remains for the recolorable Light/Dark/Monochrome
/// variants and as the icon-geometry constants).
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

  /// The bundled brand artwork (see `pubspec.yaml` assets).
  static const String kBrandIconAsset = 'assets/brand/matheasy_app_icon.png';

  /// Edge length of the (square) avatar tile in logical pixels.
  final double size;

  /// Accessibility label. Defaults to the brand name.
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          size * MatheasyAppIcon.radiusFraction,
        ),
        child: Image.asset(
          kBrandIconAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
