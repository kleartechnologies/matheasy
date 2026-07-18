import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// The Matheasy brand mark — the **M**.
///
/// A bold, italic, geometric M: the letterform from the Matheasy logo, drawn
/// flat for product UI.
///
/// ## Why this is a construction, not a trace
///
/// The logo artwork is a 3D render — the M sits on a plaque rotated ≈4° and
/// carries a long shadow, all under a true perspective projection. Tracing its
/// silhouette and un-projecting it affinely (which is the best any 2D un-shear
/// can do) yields non-parallel stems and drunk edges: it reads as a bad scan of
/// the logo rather than the logo. So the geometry below is *constructed* clean —
/// parallel stems, one slant, real corner rounding — from proportions **measured
/// off the artwork**:
///
/// | measured on the artwork          | here      |
/// |----------------------------------|-----------|
/// | stem width (L 34 / R 29 of h=100)| `_S` 31   |
/// | inner V vertex depth             | `_Vi` 76  |
/// | outer V notch depth              | `_Vd` 42  |
/// | stem shear (26° screen − 4° tilt)| `_slant` 21° |
/// | width : height (upright)         | `_W` 104  |
///
/// That is the standard way a flat UI variant of a rendered logo is derived: the
/// letterform's character is preserved, its render artifacts are not. The long
/// shadow and the extrusion are deliberately absent — they turn to mud below
/// ~32px and cannot recolor for dark mode.
///
/// This is the single source of truth for the flat mark geometry. [MatheasyLogo]
/// (the wordmark lockups) and the splash mark paint through [MatheasyMarkPainter].
///
/// Note: the shipped **app icon** and the in-app **brand avatar** no longer use
/// this vector — they show the official rendered artwork (the M with a deep-forest
/// outline and long shadow on the emerald field; `brand/matheasy-app-icon-source.png`).
/// The brand system intends that split: the icon carries the 3D treatment, this
/// flat mark stays recolorable and survives 24px and dark mode.
class MatheasyMark extends StatelessWidget {
  const MatheasyMark({
    super.key,
    this.size = 40,
    this.color = AppColors.primary,
    this.semanticLabel,
  });

  /// Edge length of the (square) mark box in logical pixels. The M is centred
  /// inside it — see [MatheasyMarkPainter] for the aspect.
  final double size;

  /// Fill color of the mark. Defaults to the brand identity emerald.
  final Color color;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: MatheasyMarkPainter(color: color)),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: child);
    }
    return Semantics(label: semanticLabel, image: true, child: child);
  }
}

/// Paints the M into any square canvas. Reused by the app-icon generator so the
/// icon and the in-app mark never drift.
class MatheasyMarkPainter extends CustomPainter {
  const MatheasyMarkPainter({this.color = AppColors.primary});

  final Color color;

  /// The mark's native viewBox edge. The M is height-centred inside it and
  /// spans the full width (its sheared aspect is ≈1.42:1).
  static const double viewBox = 100;

  /// The constructed M, in the [viewBox] square. Generated from the measured
  /// proportions documented on [MatheasyMark].
  ///
  /// Public so the geometry can be measured directly in tests without mocking a
  /// [Canvas].
  static Path buildPath() {
    return Path()
      ..moveTo(25.20, 19.47)
      ..quadraticBezierTo(26.96, 14.88, 31.88, 14.88)
      ..lineTo(45.92, 14.88)
      ..quadraticBezierTo(50.84, 14.88, 51.06, 19.80)
      ..lineTo(52.05, 41.93)
      ..quadraticBezierTo(52.16, 44.38, 53.71, 42.47)
      ..lineTo(73.02, 18.70)
      ..quadraticBezierTo(76.12, 14.88, 81.04, 14.88)
      ..lineTo(95.08, 14.88)
      ..quadraticBezierTo(100.00, 14.88, 98.24, 19.47)
      ..lineTo(74.80, 80.53)
      ..quadraticBezierTo(73.04, 85.12, 68.12, 85.12)
      ..lineTo(56.19, 85.12)
      ..quadraticBezierTo(51.27, 85.12, 53.03, 80.53)
      ..lineTo(61.71, 57.91)
      ..quadraticBezierTo(62.59, 55.62, 60.53, 56.95)
      ..lineTo(45.06, 66.93)
      ..quadraticBezierTo(42.99, 68.26, 41.48, 66.32)
      ..lineTo(34.61, 57.55)
      ..quadraticBezierTo(33.09, 55.62, 32.21, 57.91)
      ..lineTo(23.53, 80.53)
      ..quadraticBezierTo(21.77, 85.12, 16.86, 85.12)
      ..lineTo(4.92, 85.12)
      ..quadraticBezierTo(0.00, 85.12, 1.76, 80.53)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform scale from the 100×100 brand viewBox to the target square.
    final scale = size.shortestSide / viewBox;
    canvas.save();
    // Centre the mark if the canvas is not perfectly square.
    canvas.translate(
      (size.width - viewBox * scale) / 2,
      (size.height - viewBox * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawPath(
      buildPath(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MatheasyMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
