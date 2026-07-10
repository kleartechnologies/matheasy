import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'matheasy_mark.dart';

/// The official Matheasy app icon — the **Emerald** variant.
///
/// A white, two-tone [MatheasyMark] centred on an Emerald gradient
/// rounded-square tile (Emerald 500 → 600), tuned to the brand system's
/// construction spec: ~22.4% corner radius, ~44% safe area, one gesture. This
/// widget is the single source of truth for the icon; the exported iOS/Android
/// raster assets are generated from the exact same [MatheasyMarkPainter] (see
/// `tool/generate_app_icons.dart`).
///
/// Pass a solid [background] (e.g. white, ink) for the Light / Dark / Monochrome
/// variants, or a [gradient]; when both are null the Emerald [iconGradient] is
/// used. Set [rounded] to false to render a full-bleed square — iOS masks its
/// own corners, so the shipped iOS raster is generated square.
class MatheasyAppIcon extends StatelessWidget {
  const MatheasyAppIcon({
    super.key,
    this.size = 120,
    this.rounded = true,
    this.gradient,
    this.background,
    this.foreground = AppColors.white,
  });

  final double size;
  final bool rounded;

  /// Tile gradient. Ignored when [background] is set. Defaults to the brand
  /// Emerald [AppColors.iconGradient].
  final Gradient? gradient;

  /// Solid tile fill for the Light / Dark / Monochrome variants. When set it
  /// overrides [gradient].
  final Color? background;

  /// Mark color. White for the Emerald / Dark variants; Emerald for the Light
  /// variant; Ink for Monochrome.
  final Color foreground;

  /// Corner radius as a fraction of the tile edge (iOS superellipse ≈ 22.4%).
  static const double radiusFraction = 0.2237;

  /// The mark occupies this fraction of the tile edge (optically balanced
  /// inside the safe area).
  static const double markFraction = 0.58;

  @override
  Widget build(BuildContext context) {
    final fill = background == null ? (gradient ?? AppColors.iconGradient) : null;
    return Semantics(
      label: 'Matheasy app icon',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          gradient: fill,
          borderRadius: rounded
              ? BorderRadius.circular(size * radiusFraction)
              : null,
        ),
        alignment: Alignment.center,
        child: MatheasyMark(size: size * markFraction, color: foreground),
      ),
    );
  }
}
