import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'matheasy_mark.dart';

/// The official Matheasy app icon — **Concept C (Recommended)**.
///
/// A white [MatheasyMark] centred in a Brand Blue rounded-square tile, tuned to
/// the brand system's construction spec: 22.5% corner radius, ~12% safe area,
/// one colour. This widget is the single source of truth for the icon; the
/// exported iOS/Android raster assets are generated from the exact same
/// [MatheasyMarkPainter] (see `tool/generate_app_icons.dart`).
///
/// Set [rounded] to false to render a full-bleed square — iOS masks its own
/// corners, so the shipped iOS raster is generated square.
class MatheasyAppIcon extends StatelessWidget {
  const MatheasyAppIcon({
    super.key,
    this.size = 120,
    this.rounded = true,
    this.background = AppColors.primary,
    this.foreground = AppColors.white,
  });

  final double size;
  final bool rounded;
  final Color background;
  final Color foreground;

  /// Corner radius as a fraction of the tile edge (brand spec: 22.5%).
  static const double radiusFraction = 0.225;

  /// The mark occupies this fraction of the tile edge (optically balanced
  /// inside the 12% safe area).
  static const double markFraction = 0.56;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Matheasy app icon',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
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
