import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../../../core/theme/app_radius.dart';
import '../../../../../../../core/theme/app_spacing.dart';
import '../../../../../../../core/theme/app_typography.dart';
import '../../../../../domain/animation/scene_spec.dart';
import '../../../math_text.dart';
import '../engine_palette.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the balance-scale visual for linear
/// equations. The beam stays LEVEL: whatever you do to one side you do to the
/// other, so the two sides always weigh the same. It gives a gentle "weigh-in"
/// settle as the beat plays, then the solved value rises on the answer beat.
///
/// The side chips are the VERIFIED equation sides supplied by the builder — the
/// scale never computes anything.
class BalanceScaleView extends StatelessWidget {
  const BalanceScaleView({
    super.key,
    required this.scene,
    required this.progress,
    required this.showAnswer,
    required this.palette,
  });

  final SceneObject scene;
  final Animation<double> progress;
  final bool showAnswer;
  final EnginePalette palette;

  @override
  Widget build(BuildContext context) {
    final left = scene.labels['left'] ?? '';
    final right = scene.labels['right'] ?? '';
    final answer = scene.labels['answer'] ?? '';
    final labelStyle =
        AppTypography.headingSmall.copyWith(color: palette.text);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        Widget pan(String latex, double cx) => Positioned(
              left: w * cx - w * 0.16,
              top: h * 0.50,
              width: w * 0.32,
              child: Center(
                child: MathText(
                  latex,
                  style: labelStyle,
                  alignment: Alignment.center,
                ),
              ),
            );

        return Stack(
          children: [
            // Only the beam/pans repaint each frame; the LaTeX side chips below
            // are built once (no per-frame flutter_math re-parse).
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: progress,
                  builder: (context, _) => CustomPaint(
                    painter: _BalancePainter(
                      progress:
                          Curves.easeOut.transform(progress.value.clamp(0, 1)),
                      palette: palette,
                    ),
                  ),
                ),
              ),
            ),
            pan(left, 0.26),
            pan(right, 0.74),
            if (showAnswer && answer.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: h * 0.04,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: AppRadius.pillRadius,
                      ),
                      child: MathText(
                        answer,
                        style: AppTypography.bodyMedium
                            .copyWith(color: palette.onAccent),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter({required this.progress, required this.palette});

  final double progress;
  final EnginePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final pivot = Offset(w * 0.5, h * 0.30);

    // A subtle weigh-in that settles perfectly level (the teaching point).
    final tilt = 0.05 * (1 - Curves.easeOut.transform(progress.clamp(0, 1))) *
        math.sin(progress * math.pi * 2);

    final stroke = Paint()
      ..color = palette.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final fillAccent = Paint()..color = palette.accent;

    // Fulcrum (triangle) + base.
    final tri = Path()
      ..moveTo(pivot.dx, pivot.dy)
      ..lineTo(pivot.dx - w * 0.06, h * 0.60)
      ..lineTo(pivot.dx + w * 0.06, h * 0.60)
      ..close();
    canvas.drawPath(tri, Paint()..color = palette.accentSoft);
    canvas.drawPath(tri, stroke);
    canvas.drawLine(Offset(w * 0.30, h * 0.60), Offset(w * 0.70, h * 0.60),
        stroke..strokeWidth = 4);

    // Beam (rotated slightly about the pivot).
    final halfBeam = w * 0.36;
    final dir = Offset(math.cos(tilt), math.sin(tilt));
    final beamL = pivot - dir * halfBeam;
    final beamR = pivot + dir * halfBeam;
    canvas.drawLine(beamL, beamR, stroke..strokeWidth = 4);
    canvas.drawCircle(pivot, 5, fillAccent);

    // Pan hangers + pans, hung inboard from the beam ends.
    final panLBeam = pivot - dir * (halfBeam * 0.72);
    final panRBeam = pivot + dir * (halfBeam * 0.72);
    _drawPan(canvas, panLBeam, h, stroke, palette);
    _drawPan(canvas, panRBeam, h, stroke, palette);
  }

  void _drawPan(
      Canvas canvas, Offset beamPoint, double h, Paint stroke, EnginePalette p) {
    final panY = h * 0.48;
    final center = Offset(beamPoint.dx, panY);
    canvas.drawLine(beamPoint, center, stroke..strokeWidth = 2);
    final rect = Rect.fromCenter(
        center: Offset(center.dx, panY + 4), width: 90, height: 30);
    final pan = Path()
      ..moveTo(rect.left, rect.top)
      ..quadraticBezierTo(
          rect.center.dx, rect.bottom + 8, rect.right, rect.top);
    canvas.drawPath(
        pan, Paint()..color = p.accentSoft..style = PaintingStyle.fill);
    canvas.drawPath(
        pan,
        stroke
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_BalancePainter old) =>
      old.progress != progress || old.palette != palette;
}
