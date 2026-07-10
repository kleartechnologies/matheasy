import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/visual_models.dart';

/// Theme-derived colors handed to [ConceptPainter] (painters can't read
/// `BuildContext`). Built by the Tier 3 explorer from the design tokens.
@immutable
class ConceptPalette {
  const ConceptPalette({
    required this.grid,
    required this.axis,
    required this.stroke,
    required this.fill,
    required this.accent,
  });

  final Color grid;
  final Color axis;
  final Color stroke;
  final Color fill;
  final Color accent;

  @override
  bool operator ==(Object other) =>
      other is ConceptPalette &&
      other.grid == grid &&
      other.axis == axis &&
      other.stroke == stroke &&
      other.fill == fill &&
      other.accent == accent;

  @override
  int get hashCode => Object.hash(grid, axis, stroke, fill, accent);
}

/// Paints a [VisualConcept] — the Tier 3 drawable metadata — with native
/// Canvas calls only. Every kind guards its parameters and simply paints
/// nothing sensible-less, so malformed AI metadata can never crash a frame.
class ConceptPainter extends CustomPainter {
  const ConceptPainter({required this.concept, required this.palette});

  final VisualConcept concept;
  final ConceptPalette palette;

  static const double _pad = 24;

  @override
  void paint(Canvas canvas, Size size) {
    switch (concept.kind) {
      case VisualConceptKind.linearGraph:
        _paintLinear(canvas, size);
      case VisualConceptKind.parabolaGraph:
        _paintParabola(canvas, size, shadeArea: false);
      case VisualConceptKind.areaUnderCurve:
        _paintParabola(canvas, size, shadeArea: true);
      case VisualConceptKind.numberLine:
        _paintNumberLine(canvas, size);
      case VisualConceptKind.fractionBar:
        _paintFractionBar(canvas, size);
      case VisualConceptKind.unitCircle:
        _paintUnitCircle(canvas, size);
      case VisualConceptKind.barChart:
        _paintBarChart(canvas, size);
      case VisualConceptKind.geometryShape:
        _paintGeometryShape(canvas, size);
      case VisualConceptKind.generic:
        break; // The explorer renders a card instead of a canvas.
    }
  }

  // ---- Function graphs ------------------------------------------------------

  void _paintLinear(Canvas canvas, Size size) {
    final m = concept.param('slope', fallback: 1);
    final b = concept.param('intercept');
    final xMin = concept.param('xMin', fallback: -5);
    final xMax = concept.param('xMax', fallback: 5);
    if (xMax <= xMin) return;

    _paintCurve(
      canvas,
      size,
      xMin: xMin,
      xMax: xMax,
      f: (x) => m * x + b,
      markers: [
        Offset(0, b), // y-intercept
        if (m != 0) Offset(-b / m, 0), // root
      ],
    );
  }

  void _paintParabola(Canvas canvas, Size size, {required bool shadeArea}) {
    final a = concept.param('a', fallback: 1);
    final b = concept.param('b');
    final c = concept.param('c');
    double f(double x) => a * x * x + b * x + c;

    // Frame the interesting region: the vertex plus the roots when real.
    final vertexX = a == 0 ? 0.0 : -b / (2 * a);
    final disc = b * b - 4 * a * c;
    final roots = <double>[
      if (a != 0 && disc >= 0) ...[
        (-b - math.sqrt(disc)) / (2 * a),
        (-b + math.sqrt(disc)) / (2 * a),
      ],
    ];
    // The integration bounds must be inside the window, or the shaded area
    // gets chopped at the frame edge (areaUnderCurve for ∫₀⁴ with vertex-only
    // framing would otherwise stop at x=3).
    final from = concept.param(
      'from',
      fallback: roots.isNotEmpty ? roots.first : vertexX - 3,
    );
    final to = concept.param(
      'to',
      fallback: roots.length > 1 ? roots.last : vertexX + 3,
    );

    var span = 3.0;
    for (final r in roots) {
      span = math.max(span, (r - vertexX).abs() + 1.5);
    }
    if (shadeArea) {
      span = math.max(span, (from - vertexX).abs() + 1);
      span = math.max(span, (to - vertexX).abs() + 1);
    }
    final xMin = concept.param('xMin', fallback: vertexX - span);
    final xMax = concept.param('xMax', fallback: vertexX + span);
    if (!(xMax > xMin) || !xMin.isFinite || !xMax.isFinite) return;

    _paintCurve(
      canvas,
      size,
      xMin: xMin,
      xMax: xMax,
      f: f,
      markers: [for (final r in roots) Offset(r, 0)],
      shade: shadeArea && to > from ? (from, to) : null,
    );
  }

  /// Shared curve plotting: grid, axes, sampled polyline, optional shaded
  /// region between `shade.$1` and `shade.$2`, and accent marker dots.
  void _paintCurve(
    Canvas canvas,
    Size size, {
    required double xMin,
    required double xMax,
    required double Function(double) f,
    List<Offset> markers = const [],
    (double, double)? shade,
  }) {
    const samples = 64;
    final xs = [
      for (var i = 0; i <= samples; i++) xMin + (xMax - xMin) * i / samples,
    ];
    final ys = [for (final x in xs) f(x)];
    // A non-finite sample (overflow / asymptote) would poison the whole
    // min/max and every mapped pixel — bail rather than draw garbage.
    if (ys.any((y) => !y.isFinite)) return;
    var yMin = ys.reduce(math.min);
    var yMax = ys.reduce(math.max);
    // Always include the x-axis so roots/intercepts stay visible.
    yMin = math.min(yMin, 0);
    yMax = math.max(yMax, 0);
    if (yMax - yMin < 1e-9) {
      yMin -= 1;
      yMax += 1;
    }
    final mapper = _Mapper(size, xMin, xMax, yMin, yMax);

    _grid(canvas, size, mapper);
    _axes(canvas, mapper);

    if (shade != null) {
      final (from, to) = shade;
      final path = Path()..moveTo(mapper.x(from), mapper.y(0));
      for (final x in xs.where((x) => x >= from && x <= to)) {
        path.lineTo(mapper.x(x), mapper.y(f(x)));
      }
      path
        ..lineTo(mapper.x(to), mapper.y(f(to)))
        ..lineTo(mapper.x(to), mapper.y(0))
        ..close();
      canvas.drawPath(path, Paint()..color = palette.fill);
    }

    final curve = Path()..moveTo(mapper.x(xs.first), mapper.y(ys.first));
    for (var i = 1; i < xs.length; i++) {
      curve.lineTo(mapper.x(xs[i]), mapper.y(ys[i]));
    }
    canvas.drawPath(curve, _strokePaint(palette.stroke, 2.5));

    for (final marker in markers) {
      canvas.drawCircle(
        Offset(mapper.x(marker.dx), mapper.y(marker.dy)),
        5,
        Paint()..color = palette.accent,
      );
    }
  }

  // ---- Number line -----------------------------------------------------------

  void _paintNumberLine(Canvas canvas, Size size) {
    final min = concept.param('min');
    final max = concept.param('max', fallback: 10);
    final value = concept.param('value', fallback: (min + max) / 2);
    if (!(max > min) || !min.isFinite || !max.isFinite) return;

    final y = size.height / 2;
    final left = Offset(_pad, y);
    final right = Offset(size.width - _pad, y);
    final line = _strokePaint(palette.axis, 2);
    canvas.drawLine(left, right, line);
    _arrowHead(canvas, right, 0, line);
    _arrowHead(canvas, left, math.pi, line);

    double toDx(double v) =>
        _pad + (v - min) / (max - min) * (size.width - 2 * _pad);

    // Integer ticks when readable, else quarters.
    final range = max - min;
    final tick = range <= 20 ? 1.0 : range / 4;
    for (final v in _ticks(min, max, tick)) {
      final dx = toDx(v);
      canvas.drawLine(
        Offset(dx, y - 6),
        Offset(dx, y + 6),
        _strokePaint(palette.grid, 1.5),
      );
    }

    final valueDx = toDx(value.clamp(min, max));
    canvas.drawCircle(Offset(valueDx, y), 7, Paint()..color = palette.accent);
    canvas.drawCircle(
      Offset(valueDx, y),
      11,
      _strokePaint(palette.accent, 2),
    );
  }

  // ---- Fraction bar ------------------------------------------------------------

  void _paintFractionBar(Canvas canvas, Size size) {
    final denominator = concept.param('denominator', fallback: 1).round();
    final numerator = concept.param('numerator').round();
    if (denominator <= 0 || denominator > 64) return;

    final rect = Rect.fromLTWH(
      _pad,
      size.height / 2 - 28,
      size.width - 2 * _pad,
      56,
    );
    const radius = Radius.circular(10);
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, radius));

    final cell = rect.width / denominator;
    for (var i = 0; i < denominator; i++) {
      final cellRect =
          Rect.fromLTWH(rect.left + i * cell, rect.top, cell, rect.height);
      canvas.drawRect(
        cellRect,
        Paint()
          ..color = i < numerator.clamp(0, denominator)
              ? palette.stroke
              : palette.fill,
      );
    }
    canvas.restore();

    // Cell separators + outline on top of the fills.
    for (var i = 1; i < denominator; i++) {
      final dx = rect.left + i * cell;
      canvas.drawLine(
        Offset(dx, rect.top),
        Offset(dx, rect.bottom),
        _strokePaint(palette.axis, 1.5),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      _strokePaint(palette.axis, 2),
    );
  }

  // ---- Unit circle ---------------------------------------------------------------

  void _paintUnitCircle(Canvas canvas, Size size) {
    final angle = concept.param('angleDegrees', fallback: 30) * math.pi / 180;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - _pad;
    if (radius <= 0) return;

    // Axes through the center.
    canvas.drawLine(
      Offset(_pad / 2, center.dy),
      Offset(size.width - _pad / 2, center.dy),
      _strokePaint(palette.grid, 1.5),
    );
    canvas.drawLine(
      Offset(center.dx, _pad / 2),
      Offset(center.dx, size.height - _pad / 2),
      _strokePaint(palette.grid, 1.5),
    );

    canvas.drawCircle(center, radius, _strokePaint(palette.axis, 2));

    final point = center + Offset(math.cos(angle), -math.sin(angle)) * radius;

    // Right-triangle legs: cos along the axis, sin up to the point.
    final foot = Offset(point.dx, center.dy);
    canvas.drawLine(center, foot, _strokePaint(palette.stroke, 2));
    canvas.drawLine(foot, point, _strokePaint(palette.accent, 2));

    // The radius at the angle, the angle arc, and the point itself.
    canvas.drawLine(center, point, _strokePaint(palette.stroke, 2.5));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.3),
      0,
      -angle,
      false,
      _strokePaint(palette.accent, 2),
    );
    canvas.drawCircle(point, 6, Paint()..color = palette.accent);
  }

  // ---- Bar chart ---------------------------------------------------------------------

  void _paintBarChart(Canvas canvas, Size size) {
    final values = [for (final p in concept.points) p.y];
    if (values.isEmpty) return;
    final maxValue = values.reduce(math.max);
    if (maxValue <= 0) return;

    final chart = Rect.fromLTRB(
      _pad,
      _pad,
      size.width - _pad,
      size.height - _pad,
    );
    final slot = chart.width / values.length;
    final barWidth = slot * 0.6;

    for (var i = 0; i < values.length; i++) {
      final height = (values[i] / maxValue).clamp(0.0, 1.0) * chart.height;
      final bar = Rect.fromLTWH(
        chart.left + i * slot + (slot - barWidth) / 2,
        chart.bottom - height,
        barWidth,
        height,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          bar,
          topLeft: const Radius.circular(6),
          topRight: const Radius.circular(6),
        ),
        Paint()..color = i.isEven ? palette.stroke : palette.accent,
      );
    }
    canvas.drawLine(
      chart.bottomLeft,
      chart.bottomRight,
      _strokePaint(palette.axis, 2),
    );
  }

  // ---- Geometry shape -----------------------------------------------------------------

  void _paintGeometryShape(Canvas canvas, Size size) {
    final points = concept.points;
    if (points.length < 3) return;

    var xMin = points.first.x, xMax = points.first.x;
    var yMin = points.first.y, yMax = points.first.y;
    for (final p in points) {
      xMin = math.min(xMin, p.x);
      xMax = math.max(xMax, p.x);
      yMin = math.min(yMin, p.y);
      yMax = math.max(yMax, p.y);
    }
    if (xMax - xMin < 1e-9 || yMax - yMin < 1e-9) return;

    // Uniform scale so the shape keeps its proportions, centered in the canvas.
    final scale = math.min(
      (size.width - 2 * _pad) / (xMax - xMin),
      (size.height - 2 * _pad) / (yMax - yMin),
    );
    final offset = Offset(
      (size.width - (xMax - xMin) * scale) / 2,
      (size.height - (yMax - yMin) * scale) / 2,
    );
    Offset map(VisualPoint p) => Offset(
          offset.dx + (p.x - xMin) * scale,
          size.height - offset.dy - (p.y - yMin) * scale,
        );

    final path = Path()..moveTo(map(points.first).dx, map(points.first).dy);
    for (final p in points.skip(1)) {
      path.lineTo(map(p).dx, map(p).dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = palette.fill);
    canvas.drawPath(path, _strokePaint(palette.stroke, 2.5));
    for (final p in points) {
      canvas.drawCircle(map(p), 4.5, Paint()..color = palette.accent);
    }
  }

  // ---- Shared primitives ------------------------------------------------------------------

  void _grid(Canvas canvas, Size size, _Mapper mapper) {
    final paint = _strokePaint(palette.grid, 1);
    for (final x
        in _ticks(mapper.xMin, mapper.xMax, _niceStep(mapper.xMax - mapper.xMin))) {
      canvas.drawLine(
        Offset(mapper.x(x), 0),
        Offset(mapper.x(x), size.height),
        paint,
      );
    }
    for (final y
        in _ticks(mapper.yMin, mapper.yMax, _niceStep(mapper.yMax - mapper.yMin))) {
      canvas.drawLine(
        Offset(0, mapper.y(y)),
        Offset(size.width, mapper.y(y)),
        paint,
      );
    }
  }

  /// Evenly spaced tick values in [min, max], generated by integer index so a
  /// step below the floating-point ulp at a large magnitude can never stall
  /// the loop (e.g. min = 1e16, step = 1 froze `x += step`). Capped so a
  /// pathological range can't emit thousands of lines.
  static Iterable<double> _ticks(double min, double max, double step) sync* {
    if (!step.isFinite || step <= 0 || !min.isFinite || !max.isFinite) return;
    final start = (min / step).ceil() * step;
    final count = ((max - start) / step).floor();
    if (!count.isFinite || count < 0 || count > 400) return;
    for (var i = 0; i <= count; i++) {
      yield start + i * step;
    }
  }

  void _axes(Canvas canvas, _Mapper mapper) {
    final paint = _strokePaint(palette.axis, 2);
    if (mapper.yMin <= 0 && mapper.yMax >= 0) {
      canvas.drawLine(
        Offset(mapper.x(mapper.xMin), mapper.y(0)),
        Offset(mapper.x(mapper.xMax), mapper.y(0)),
        paint,
      );
    }
    if (mapper.xMin <= 0 && mapper.xMax >= 0) {
      canvas.drawLine(
        Offset(mapper.x(0), mapper.y(mapper.yMin)),
        Offset(mapper.x(0), mapper.y(mapper.yMax)),
        paint,
      );
    }
  }

  void _arrowHead(Canvas canvas, Offset tip, double angle, Paint paint) {
    const length = 8.0;
    for (final spread in [math.pi * 0.8, -math.pi * 0.8]) {
      canvas.drawLine(
        tip,
        tip + Offset(math.cos(angle + spread), math.sin(angle + spread)) * length,
        paint,
      );
    }
  }

  /// A grid spacing that yields ~4–10 lines for any data range.
  double _niceStep(double range) {
    if (range <= 0) return 1;
    final raw = range / 8;
    final magnitude = math.pow(10, (math.log(raw) / math.ln10).floor());
    final normalized = raw / magnitude;
    final nice = normalized < 1.5
        ? 1
        : normalized < 3.5
            ? 2
            : normalized < 7.5
                ? 5
                : 10;
    return (nice * magnitude).toDouble();
  }

  Paint _strokePaint(Color color, double width) => Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  @override
  bool shouldRepaint(ConceptPainter oldDelegate) =>
      oldDelegate.concept != concept || oldDelegate.palette != palette;
}

/// Maps data coordinates onto canvas pixels (y-axis flipped), with padding.
class _Mapper {
  _Mapper(this.size, this.xMin, this.xMax, this.yMin, this.yMax);

  final Size size;
  final double xMin, xMax, yMin, yMax;

  static const double _pad = ConceptPainter._pad;

  double x(double v) =>
      _pad + (v - xMin) / (xMax - xMin) * (size.width - 2 * _pad);

  double y(double v) =>
      size.height - _pad - (v - yMin) / (yMax - yMin) * (size.height - 2 * _pad);
}
