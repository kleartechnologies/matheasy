import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../../domain/animation/scene_spec.dart';
import '../engine_palette.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the number-driven scene painters
/// (curves, fraction bars, pies, bars, number lines). Every one only *reveals*
/// verified values by [progress]; none computes math. All clamp/guard their
/// inputs so malformed data paints nothing rather than crash.

// ---------------------------------------------------------------------------
// Function curve / parabola
// ---------------------------------------------------------------------------

class CurveSceneView extends StatelessWidget {
  const CurveSceneView({
    super.key,
    required this.scene,
    required this.progress,
    required this.palette,
  });

  final SceneObject scene;
  final Animation<double> progress;
  final EnginePalette palette;

  @override
  Widget build(BuildContext context) => _ScenePaint(
        progress: progress,
        painter: (p) => _CurvePainter(
          points: scene.points,
          roots: [
            for (var i = 0; i < scene.param('roots').round() && i < 3; i++)
              scene.param('rootX$i'),
          ],
          vertex: scene.param('hasVertex') > 0
              ? Offset(scene.param('vertexX'), scene.param('vertexY'))
              : null,
          progress: p,
          palette: palette,
        ),
      );
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.roots,
    required this.vertex,
    required this.progress,
    required this.palette,
  });

  final List<Offset> points;
  final List<double> roots;
  final Offset? vertex;
  final double progress;
  final EnginePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    const pad = 16.0;
    var minX = points.first.dx, maxX = points.first.dx;
    var minY = points.first.dy, maxY = points.first.dy;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    // Always include the axes for context.
    minX = math.min(minX, 0);
    maxX = math.max(maxX, 0);
    minY = math.min(minY, 0);
    maxY = math.max(maxY, 0);
    final spanX = maxX - minX, spanY = maxY - minY;
    if (spanX <= 0 || spanY <= 0) return;

    double mx(double x) => pad + (x - minX) / spanX * (size.width - 2 * pad);
    double my(double y) =>
        size.height - pad - (y - minY) / spanY * (size.height - 2 * pad);

    // Axes.
    final axis = Paint()
      ..color = palette.axis
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(mx(minX), my(0)), Offset(mx(maxX), my(0)), axis);
    canvas.drawLine(Offset(mx(0), my(minY)), Offset(mx(0), my(maxY)), axis);

    // The curve, revealed left→right by progress.
    final n = (points.length * progress.clamp(0, 1)).ceil().clamp(2, points.length);
    final path = Path()..moveTo(mx(points[0].dx), my(points[0].dy));
    for (var i = 1; i < n; i++) {
      path.lineTo(mx(points[i].dx), my(points[i].dy));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.accent
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // Roots + vertex pop in once the curve is mostly drawn.
    final markerAlpha = ((progress - 0.6) / 0.4).clamp(0.0, 1.0);
    if (markerAlpha > 0) {
      final dot = Paint()..color = palette.warn.withValues(alpha: markerAlpha);
      for (final r in roots) {
        if (r >= minX && r <= maxX) {
          canvas.drawCircle(Offset(mx(r), my(0)), 5, dot);
        }
      }
      if (vertex != null) {
        canvas.drawCircle(
          Offset(mx(vertex!.dx), my(vertex!.dy)),
          5,
          Paint()..color = palette.accent.withValues(alpha: markerAlpha),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.progress != progress || old.palette != palette || old.points != points;
}

// ---------------------------------------------------------------------------
// Fraction bar
// ---------------------------------------------------------------------------

class FractionBarSceneView extends StatelessWidget {
  const FractionBarSceneView({
    super.key,
    required this.scene,
    required this.progress,
    required this.palette,
  });

  final SceneObject scene;
  final Animation<double> progress;
  final EnginePalette palette;

  @override
  Widget build(BuildContext context) => _ScenePaint(
        progress: progress,
        painter: (p) => _FractionBarPainter(
          numerator: scene.param('numerator').round().abs(),
          denominator: scene.param('denominator').round(),
          progress: p,
          palette: palette,
        ),
      );
}

class _FractionBarPainter extends CustomPainter {
  _FractionBarPainter({
    required this.numerator,
    required this.denominator,
    required this.progress,
    required this.palette,
  });

  final int numerator;
  final int denominator;
  final double progress;
  final EnginePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (denominator < 1 || denominator > 24) return;
    final barW = size.width * 0.86;
    final barH = math.min(size.height * 0.4, 84.0);
    final left = (size.width - barW) / 2;
    final top = (size.height - barH) / 2;
    final cellW = barW / denominator;
    const radius = Radius.circular(10);

    final shadeCount = numerator * progress.clamp(0, 1);
    for (var i = 0; i < denominator; i++) {
      final cell = Rect.fromLTWH(left + i * cellW, top, cellW, barH)
          .deflate(1.5);
      final filled = (i + 1) <= shadeCount;
      final partial = !filled && i < shadeCount;
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell, radius),
        Paint()..color = palette.fill,
      );
      if (filled || partial) {
        final frac = filled ? 1.0 : (shadeCount - i).clamp(0.0, 1.0);
        final fillRect =
            Rect.fromLTWH(cell.left, cell.top, cell.width * frac, cell.height);
        canvas.drawRRect(
          RRect.fromRectAndRadius(fillRect, radius),
          Paint()..color = palette.accent,
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(cell, radius),
        Paint()
          ..color = palette.grid
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
    _label(canvas, size, '$numerator/$denominator', top + barH + 12, palette);
  }

  @override
  bool shouldRepaint(_FractionBarPainter old) =>
      old.progress != progress || old.palette != palette;
}

// ---------------------------------------------------------------------------
// Pie chart
// ---------------------------------------------------------------------------

class PieSceneView extends StatelessWidget {
  const PieSceneView({
    super.key,
    required this.scene,
    required this.progress,
    required this.palette,
  });

  final SceneObject scene;
  final Animation<double> progress;
  final EnginePalette palette;

  @override
  Widget build(BuildContext context) {
    final num = scene.param('numerator');
    final den = scene.param('denominator', fallback: 1);
    final pct = scene.params.containsKey('percent')
        ? scene.param('percent') / 100
        : (den != 0 ? num / den : 0.0);
    return _ScenePaint(
      progress: progress,
      painter: (p) => _PiePainter(
        fraction: pct.clamp(0.0, 1.0),
        label: scene.labels['center'] ??
            (scene.params.containsKey('percent')
                ? '${scene.param('percent').round()}%'
                : '${num.round()}/${den.round()}'),
        progress: p,
        palette: palette,
      ),
    );
  }
}

/// Wraps a progress-driven [CustomPainter] so ONLY the painter repaints each
/// frame (via its own AnimatedBuilder + RepaintBoundary) — the eased progress is
/// handed to [painter]. Keeps any static sibling widgets out of the per-frame
/// rebuild (e.g. the balance-scale's LaTeX side chips).
class _ScenePaint extends StatelessWidget {
  const _ScenePaint({required this.progress, required this.painter});

  final Animation<double> progress;
  final CustomPainter Function(double p) painter;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: progress,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: painter(Curves.easeOut.transform(progress.value.clamp(0, 1))),
          ),
        ),
      );
}

class _PiePainter extends CustomPainter {
  _PiePainter({
    required this.fraction,
    required this.label,
    required this.progress,
    required this.palette,
  });

  final double fraction;
  final String label;
  final double progress;
  final EnginePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.36;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(center, radius, Paint()..color = palette.fill);
    final sweep = 2 * math.pi * fraction * progress.clamp(0, 1);
    canvas.drawArc(rect, -math.pi / 2, sweep, true, Paint()..color = palette.accent);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = palette.stroke
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    _label(canvas, size, label, center.dy + radius + 14, palette);
  }

  @override
  bool shouldRepaint(_PiePainter old) =>
      old.progress != progress || old.palette != palette;
}

// ---------------------------------------------------------------------------
// Bar chart
// ---------------------------------------------------------------------------

class BarChartSceneView extends StatelessWidget {
  const BarChartSceneView({
    super.key,
    required this.scene,
    required this.progress,
    required this.palette,
  });

  final SceneObject scene;
  final Animation<double> progress;
  final EnginePalette palette;

  @override
  Widget build(BuildContext context) => _ScenePaint(
        progress: progress,
        painter: (p) => _BarPainter(
          values: [for (final p in scene.points) p.dy],
          progress: p,
          palette: palette,
        ),
      );
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.values,
    required this.progress,
    required this.palette,
  });

  final List<double> values;
  final double progress;
  final EnginePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || values.length > 20) return;
    final maxV = values.map((v) => v.abs()).fold<double>(0, math.max);
    if (maxV <= 0) return;
    const pad = 18.0;
    final plotH = size.height - 2 * pad;
    final slot = (size.width - 2 * pad) / values.length;
    final barW = slot * 0.6;
    canvas.drawLine(Offset(pad, size.height - pad),
        Offset(size.width - pad, size.height - pad), Paint()..color = palette.axis);
    for (var i = 0; i < values.length; i++) {
      final h = plotH * (values[i].abs() / maxV) * progress.clamp(0, 1);
      final x = pad + slot * i + (slot - barW) / 2;
      final rect = Rect.fromLTWH(x, size.height - pad - h, barW, h);
      canvas.drawRRect(
        RRect.fromRectAndCorners(rect,
            topLeft: const Radius.circular(6),
            topRight: const Radius.circular(6)),
        Paint()..color = palette.accent,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.progress != progress || old.palette != palette;
}

// ---------------------------------------------------------------------------
// Number line
// ---------------------------------------------------------------------------

class NumberLineSceneView extends StatelessWidget {
  const NumberLineSceneView({
    super.key,
    required this.scene,
    required this.progress,
    required this.palette,
  });

  final SceneObject scene;
  final Animation<double> progress;
  final EnginePalette palette;

  @override
  Widget build(BuildContext context) => _ScenePaint(
        progress: progress,
        painter: (p) => _NumberLinePainter(
          value: scene.param('value'),
          min: scene.param('min', fallback: scene.param('value') - 5),
          max: scene.param('max', fallback: scene.param('value') + 5),
          progress: p,
          palette: palette,
        ),
      );
}

class _NumberLinePainter extends CustomPainter {
  _NumberLinePainter({
    required this.value,
    required this.min,
    required this.max,
    required this.progress,
    required this.palette,
  });

  final double value, min, max, progress;
  final EnginePalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (max <= min) return;
    const pad = 24.0;
    final y = size.height / 2;
    final lineW = size.width - 2 * pad;
    canvas.drawLine(Offset(pad, y), Offset(size.width - pad, y),
        Paint()..color = palette.axis..strokeWidth = 2);
    // Ticks.
    final steps = (max - min).round().clamp(1, 12);
    for (var i = 0; i <= steps; i++) {
      final x = pad + lineW * i / steps;
      canvas.drawLine(Offset(x, y - 5), Offset(x, y + 5),
          Paint()..color = palette.grid..strokeWidth = 1.2);
    }
    // Marker slides to the value.
    final frac = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final x = pad + lineW * frac * progress.clamp(0, 1);
    canvas.drawCircle(Offset(x, y), 7, Paint()..color = palette.accent);
    _label(canvas, size, _fmt(value), y + 18, palette, atX: x);
  }

  String _fmt(double v) =>
      (v - v.roundToDouble()).abs() < 1e-6 ? '${v.round()}' : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(_NumberLinePainter old) =>
      old.progress != progress || old.palette != palette;
}

// ---------------------------------------------------------------------------
// Shared label helper
// ---------------------------------------------------------------------------

void _label(Canvas canvas, Size size, String text, double y, EnginePalette p,
    {double? atX}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: p.text,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  final x = (atX ?? size.width / 2) - tp.width / 2;
  tp.paint(canvas, Offset(x.clamp(0, size.width - tp.width), y));
}
