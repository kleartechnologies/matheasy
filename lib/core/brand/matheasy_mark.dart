import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// The Matheasy brand mark — **Concept A: Pure Radical + Equals**.
///
/// A single confident stroke that reads three ways at once: a radical (√), an
/// equals sign, and a check — *mathematics, made easy*. Ported pixel-exact from
/// the official brand system's `mk-a` symbol (100×100 viewBox), uniform stroke,
/// rounded caps and joins.
///
/// This is the single source of truth for the mark geometry. [MatheasyLogo] and
/// the app-icon tooling both paint through [MatheasyMarkPainter], so the mark on
/// the splash screen and the mark on the App Store icon are the same vector.
class MatheasyMark extends StatelessWidget {
  const MatheasyMark({
    super.key,
    this.size = 40,
    this.color = AppColors.primary,
    this.semanticLabel,
  });

  /// Edge length of the (square) mark in logical pixels.
  final double size;

  /// Stroke color of the mark. Defaults to Brand Blue.
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

/// Paints the Concept A mark into any square canvas. Reused by the app-icon
/// generator so the icon and the in-app logo never drift.
class MatheasyMarkPainter extends CustomPainter {
  const MatheasyMarkPainter({this.color = AppColors.primary});

  final Color color;

  /// Stroke width in the mark's native 100-unit space.
  static const double _strokeUnits = 11;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform scale from the 100×100 brand viewBox to the target square.
    final scale = size.shortestSide / 100.0;
    canvas.save();
    // Center the mark if the canvas is not perfectly square.
    canvas.translate(
      (size.width - 100 * scale) / 2,
      (size.height - 100 * scale) / 2,
    );
    canvas.scale(scale);

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeUnits
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Radical + equals sweep: M14 48 L34 74 L56 25 L86 25
    final radical = Path()
      ..moveTo(14, 48)
      ..lineTo(34, 74)
      ..lineTo(56, 25)
      ..lineTo(86, 25);
    canvas.drawPath(radical, stroke);

    // Equals bar: M60 47 L86 47
    final equals = Path()
      ..moveTo(60, 47)
      ..lineTo(86, 47);
    canvas.drawPath(equals, stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MatheasyMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}
