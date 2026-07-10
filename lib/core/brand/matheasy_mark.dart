import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

/// The Matheasy brand mark — **R8, "The Matheasy Mark"**.
///
/// Two ascending checkmarks drawn in a single climbing stroke: the first
/// *recedes*, the second *leads*. Repeated correctness, made kinetic — the
/// visible feeling of getting it right, again, and moving up. Ported
/// pixel-exact from the finalized brand system's `#mark` symbol (48×48 viewBox,
/// stroke 6, round caps and joins).
///
/// Two-tone is the primary, expressive treatment (the receding check drops to
/// 42% of the leading tone) — use at ≥32px. Pass [twoTone] `false` for the
/// single-tone workhorse used at ≤24px, in single-color print, and monochrome
/// contexts.
///
/// This is the single source of truth for the mark geometry. [MatheasyLogo] and
/// the app-icon tooling both paint through [MatheasyMarkPainter], so the mark on
/// the splash screen and the mark on the App Store icon are the same vector.
class MatheasyMark extends StatelessWidget {
  const MatheasyMark({
    super.key,
    this.size = 40,
    this.color = AppColors.primary,
    this.twoTone = true,
    this.semanticLabel,
  });

  /// Edge length of the (square) mark in logical pixels.
  final double size;

  /// Stroke color of the mark. Defaults to brand Emerald.
  final Color color;

  /// When true (default) the receding check drops to 42% weight. Set false for
  /// the single-tone mark at ≤24px and in single-color contexts.
  final bool twoTone;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: MatheasyMarkPainter(color: color, twoTone: twoTone),
      ),
    );
    if (semanticLabel == null) {
      return ExcludeSemantics(child: child);
    }
    return Semantics(label: semanticLabel, image: true, child: child);
  }
}

/// Paints the R8 mark into any square canvas. Reused by the app-icon generator
/// so the icon and the in-app logo never drift.
class MatheasyMarkPainter extends CustomPainter {
  const MatheasyMarkPainter({
    this.color = AppColors.primary,
    this.twoTone = true,
  });

  final Color color;

  /// When true, the receding check is drawn at [_recedeOpacity] of [color].
  final bool twoTone;

  /// The mark's native viewBox edge (48-unit grid).
  static const double _viewBox = 48;

  /// Stroke width in the mark's native 48-unit space.
  static const double _strokeUnits = 6;

  /// The receding check drops to 42% weight of the leading tone.
  static const double _recedeOpacity = 0.42;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniform scale from the 48×48 brand viewBox to the target square.
    final scale = size.shortestSide / _viewBox;
    canvas.save();
    // Center the mark if the canvas is not perfectly square.
    canvas.translate(
      (size.width - _viewBox * scale) / 2,
      (size.height - _viewBox * scale) / 2,
    );
    canvas.scale(scale);

    Paint strokeFor(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeUnits
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Receding check (first): the concept clicks, then steps back.
    final receding = Path()
      ..moveTo(5, 27.5)
      ..lineTo(12.5, 35)
      ..lineTo(20.5, 24.5);
    final recedeColor =
        twoTone ? color.withValues(alpha: color.a * _recedeOpacity) : color;
    canvas.drawPath(receding, strokeFor(recedeColor));

    // Leading check (second): full weight — mastery, leading.
    final leading = Path()
      ..moveTo(20.5, 24.5)
      ..lineTo(28.5, 33.5)
      ..lineTo(43.5, 13.5);
    canvas.drawPath(leading, strokeFor(color));

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MatheasyMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.twoTone != twoTone;
}
