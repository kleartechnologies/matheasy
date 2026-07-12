import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/result_models.dart';
import 'math_text.dart';

/// The §7 graph: an EXPANDER (collapsed by default — answer-first) that plots the
/// function. The curve is the DETERMINISTIC server-sampled polyline and the
/// marked points are the verified key points (roots, intercept, vertex), so
/// nothing on the picture is unverified. Drawn with [CustomPaint] (no charting
/// dependency), themed to the emerald accent — never red.
class ResultGraphSection extends StatefulWidget {
  const ResultGraphSection({super.key, required this.graph});

  final GraphData graph;

  @override
  State<ResultGraphSection> createState() => _ResultGraphSectionState();
}

class _ResultGraphSectionState extends State<ResultGraphSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: _open ? 'Hide graph' : 'Show graph',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    const Icon(Icons.show_chart_rounded,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Graph',
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _open ? 'Hide' : 'Show',
                      style: AppTypography.caption
                          .copyWith(color: AppColors.primary),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: AppDurations.fast,
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          size: 20, color: AppColors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: AppDurations.medium,
            curve: AppCurves.standard,
            alignment: Alignment.topCenter,
            child: _open ? _GraphBody(graph: widget.graph) : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _GraphBody extends StatelessWidget {
  const _GraphBody({required this.graph});

  final GraphData graph;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MathText(
            graph.expression,
            style: AppTypography.bodyLarge.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          AspectRatio(
            aspectRatio: 1.5,
            child: ClipRect(
              // Pan/zoom is a cheap nice-to-have on the static polyline.
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _GraphPainter(
                    curve: graph.curve,
                    keyPoints: graph.keyPoints,
                    line: AppColors.primary,
                    axis: colors.border,
                    point: AppColors.primary,
                    label: colors.textSecondary,
                    surface: colors.surface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.curve,
    required this.keyPoints,
    required this.line,
    required this.axis,
    required this.point,
    required this.label,
    required this.surface,
  });

  final List<Offset> curve;
  final List<GraphKeyPoint> keyPoints;
  final Color line;
  final Color axis;
  final Color point;
  final Color label;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    // Data bounds across the curve AND the key points.
    final xs = <double>[
      ...curve.map((p) => p.dx),
      ...keyPoints.map((p) => p.x),
    ];
    final ys = <double>[
      ...curve.map((p) => p.dy),
      ...keyPoints.map((p) => p.y),
    ];
    if (xs.isEmpty || ys.isEmpty) return;

    var minX = xs.reduce(math.min);
    var maxX = xs.reduce(math.max);
    var minY = ys.reduce(math.min);
    var maxY = ys.reduce(math.max);
    if (maxX - minX < 1e-6) {
      minX -= 1;
      maxX += 1;
    }
    if (maxY - minY < 1e-6) {
      minY -= 1;
      maxY += 1;
    }
    // Pad the y-range so the curve isn't flush against the edges.
    final padY = 0.12 * (maxY - minY);
    minY -= padY;
    maxY += padY;

    Offset toCanvas(double x, double y) => Offset(
          (x - minX) / (maxX - minX) * size.width,
          size.height - (y - minY) / (maxY - minY) * size.height,
        );

    // Axes at x=0 / y=0 when they fall within the window.
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1;
    if (minX <= 0 && maxX >= 0) {
      final px = toCanvas(0, minY).dx;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), axisPaint);
    }
    if (minY <= 0 && maxY >= 0) {
      final py = toCanvas(minX, 0).dy;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), axisPaint);
    }

    // The curve.
    if (curve.length >= 2) {
      final path = Path()..moveTo(toCanvas(curve.first.dx, curve.first.dy).dx,
          toCanvas(curve.first.dx, curve.first.dy).dy);
      for (final p in curve.skip(1)) {
        final c = toCanvas(p.dx, p.dy);
        path.lineTo(c.dx, c.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    // Key points: a haloed dot + a coordinate label.
    for (final kp in keyPoints) {
      final c = toCanvas(kp.x, kp.y);
      canvas.drawCircle(c, 6, Paint()..color = surface);
      canvas.drawCircle(c, 4.5, Paint()..color = point);
      _drawLabel(canvas, size, c, '(${_num(kp.x)}, ${_num(kp.y)})');
    }
  }

  void _drawLabel(Canvas canvas, Size size, Offset at, String text) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.caption.copyWith(color: label, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Place above-right, clamped inside the canvas.
    var dx = at.dx + 8;
    var dy = at.dy - tp.height - 6;
    if (dx + tp.width > size.width) dx = at.dx - tp.width - 8;
    if (dy < 0) dy = at.dy + 8;
    tp.paint(canvas, Offset(dx, dy));
  }

  static String _num(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.curve != curve || old.keyPoints != keyPoints || old.line != line;
}
