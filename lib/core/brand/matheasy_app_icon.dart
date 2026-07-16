import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'matheasy_mark.dart';

/// The official Matheasy app icon — the **Emerald** variant.
///
/// A white [MatheasyMark] centred on a **flat** emerald rounded-square tile, at
/// the iOS construction spec: ~22.4% corner radius, ~58% mark.
///
/// The tile is flat on purpose. The logo artwork's background measures `#06AD62`
/// → `#06AB5F` corner to corner — a ~2-unit lightness shift that is
/// imperceptible, i.e. the brand does not gradient its emerald. (The previous
/// icon ramped Emerald 500 → 600, which was a gradient the identity never had.)
///
/// The tile uses [AppColors.primary] — the identity emerald, exact to the
/// artwork. This is the one place the 2.97:1 tone is correct regardless of
/// contrast: WCAG 1.4.11 exempts logotypes. Functional UI must use
/// [AppColors.primaryAction] instead.
///
/// This widget is the single source of truth for the icon; the exported
/// iOS/Android rasters paint the same [MatheasyMarkPainter] at the same
/// [radiusFraction] / [markFraction] (see `tool/generate_app_icons.dart`).
///
/// Pass a solid [background] (e.g. white, ink) for the Light / Dark / Monochrome
/// variants. Set [rounded] to false to render a full-bleed square — iOS masks
/// its own corners, so the shipped iOS raster is generated square.
class MatheasyAppIcon extends StatelessWidget {
  const MatheasyAppIcon({
    super.key,
    this.size = 120,
    this.rounded = true,
    this.background,
    this.foreground = AppColors.white,
  });

  final double size;
  final bool rounded;

  /// Solid tile fill. Defaults to the identity emerald [AppColors.primary].
  final Color? background;

  /// Mark color. White for the Emerald / Dark variants; emerald for the Light
  /// variant; ink for Monochrome.
  final Color foreground;

  /// Corner radius as a fraction of the tile edge (iOS superellipse ≈ 22.4%).
  ///
  /// `tool/generate_app_icons.dart` reads this constant — do not fork it.
  static const double radiusFraction = 0.2237;

  /// The mark occupies this fraction of the tile edge (optically balanced
  /// inside the safe area).
  ///
  /// `tool/generate_app_icons.dart` reads this constant — do not fork it.
  static const double markFraction = 0.58;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Matheasy app icon',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? AppColors.primary,
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
