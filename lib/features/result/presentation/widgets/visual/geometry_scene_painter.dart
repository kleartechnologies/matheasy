import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/theme/app_typography.dart';
import '../../../domain/geometry_models.dart';
import '../../../domain/visual_models.dart' show VisualPoint;

/// Theme-derived colours for [GeometryScenePainter] (painters can't read a
/// `BuildContext`). Built by the geometry player from the design tokens.
@immutable
class GeometryPalette {
  const GeometryPalette({
    required this.figureStroke,
    required this.figureFill,
    required this.knownArc,
    required this.highlight,
    required this.highlightText,
    required this.vertexDot,
    required this.text,
    required this.dim,
    required this.badgeBackground,
    required this.badgeText,
    required this.tick,
  });

  /// The base shape's outline and rays.
  final Color figureStroke;

  /// The shape's translucent fill.
  final Color figureFill;

  /// Given (known) angle arcs.
  final Color knownArc;

  /// The spotlight colour for non-text marks — the unknown arc, focus ring
  /// (needs only the 3:1 graphics contrast).
  final Color highlight;

  /// The spotlight colour for on-canvas TEXT — the "?" and the revealed value
  /// (must clear AA on the card, which [highlight] may not on dark).
  final Color highlightText;

  /// Vertex markers.
  final Color vertexDot;

  /// On-canvas labels (angle values, vertex names).
  final Color text;

  /// De-emphasised elements (out of focus).
  final Color dim;

  final Color badgeBackground;
  final Color badgeText;

  /// Congruence tick marks (equal sides).
  final Color tick;

  @override
  bool operator ==(Object other) =>
      other is GeometryPalette &&
      other.figureStroke == figureStroke &&
      other.figureFill == figureFill &&
      other.knownArc == knownArc &&
      other.highlight == highlight &&
      other.highlightText == highlightText &&
      other.vertexDot == vertexDot &&
      other.text == text &&
      other.dim == dim &&
      other.badgeBackground == badgeBackground &&
      other.badgeText == badgeText &&
      other.tick == tick;

  @override
  int get hashCode => Object.hash(figureStroke, figureFill, knownArc, highlight,
      highlightText, vertexDot, text, dim, badgeBackground, badgeText, tick);
}

/// Paints a [GeometryScene] with a **per-step reveal** so the diagram itself
/// tells the story:
///
///   • step 0 (known)   — the given angles sweep in and glow;
///   • step 1 (rule)    — both givens and the gap are lit while the strip shows
///                        the rule;
///   • step 2 (unknown) — the missing angle pulses, still blank ("?");
///   • step 3 (answer)  — the computed value and an answer badge scale in,
///                        stamped directly on the figure.
///
/// Every value drawn comes from the deterministically-solved [GeometryScene];
/// the painter never computes geometry, only reveals it. Malformed index data
/// is guarded so a bad scene can't crash a frame.
class GeometryScenePainter extends CustomPainter {
  const GeometryScenePainter({
    required this.scene,
    required this.revealStep,
    required this.stepProgress,
    required this.pulse,
    required this.palette,
  });

  final GeometryScene scene;

  /// Index of the active [GeometryStep] (0…steps.length-1).
  final int revealStep;

  /// Eased 0→1 entrance progress of the active step.
  final double stepProgress;

  /// Continuous 0→1→0 value for the focus glow (held at 1 under reduced motion).
  final double pulse;

  final GeometryPalette palette;

  static const double _pad = 40;
  static const double _arcRadius = 22;

  GeometryStepFocus get _focus =>
      revealStep >= 0 && revealStep < scene.steps.length
          ? scene.steps[revealStep].focus
          : GeometryStepFocus.answer;

  Set<String> get _highlighted =>
      revealStep >= 0 && revealStep < scene.steps.length
          ? scene.steps[revealStep].highlight
          : const {};

  bool get _answerRevealed => _focus == GeometryStepFocus.answer;

  @override
  void paint(Canvas canvas, Size size) {
    final fit = _computeFit(size);
    Offset map(int i) => fit.point(scene.vertices[i]);

    _paintBaseFigure(canvas, map, fit);
    _paintTicks(canvas, map);
    _paintRightAngles(canvas, map);

    // Angles + sides last so their labels sit on top of the figure.
    for (final angle in scene.angles) {
      _paintAngle(canvas, size, map, angle);
    }
    for (final side in scene.sides) {
      _paintSide(canvas, size, map, side);
    }

    // An AREA answer has no wedge or side to stamp — the whole interior is the
    // answer, so its chip lands on the centroid.
    if (scene.unknownIsArea && _answerRevealed) {
      final t = (revealStep == scene.steps.length - 1)
          ? stepProgress.clamp(0.0, 1.0)
          : 1.0;
      _drawBadge(
        canvas,
        size,
        _centroid(map),
        '${scene.unknownLabel} = ${_fmtLen(scene.unknownValue)}',
        t,
      );
    }
  }

  // ---- Right-angle marks ----------------------------------------------------

  void _paintRightAngles(Canvas canvas, Offset Function(int) map) {
    final ring = scene.polygonRing;
    if (ring.length < 3) return;
    for (final v in scene.rightAngleVertices) {
      final pos = ring.indexOf(v);
      if (pos < 0) continue;
      final a = ring[(pos - 1 + ring.length) % ring.length];
      final b = ring[(pos + 1) % ring.length];
      if (v >= scene.vertices.length ||
          a >= scene.vertices.length ||
          b >= scene.vertices.length) {
        continue;
      }
      final vertex = map(v);
      final u1 = _unit(map(a) - vertex);
      final u2 = _unit(map(b) - vertex);
      if (u1 == Offset.zero || u2 == Offset.zero) continue;
      const s = 13.0;
      final paint = _stroke(palette.figureStroke, 1.8);
      canvas.drawLine(vertex + u1 * s, vertex + (u1 + u2) * s, paint);
      canvas.drawLine(vertex + u2 * s, vertex + (u1 + u2) * s, paint);
    }
  }

  // ---- Side-length labels ---------------------------------------------------

  void _paintSide(
    Canvas canvas,
    Size size,
    Offset Function(int) map,
    GeometrySide side,
  ) {
    final ring = scene.polygonRing;
    if (ring.length < 3 || side.edge < 0 || side.edge >= ring.length) return;
    final ai = ring[side.edge];
    final bi = ring[(side.edge + 1) % ring.length];
    if (ai >= scene.vertices.length || bi >= scene.vertices.length) return;
    final a = map(ai);
    final b = map(bi);
    final mid = (a + b) / 2;
    // Push the label just OUTSIDE the edge (away from the figure centroid).
    final centroid = _centroid(map);
    final outward = _unit(mid - centroid);
    final at = mid + (outward == Offset.zero ? const Offset(0, -1) : outward) * 16;

    final focused = _highlighted.contains(side.label);
    final dimmed = _highlighted.isNotEmpty && !focused;

    if (side.isUnknown) {
      if (_answerRevealed) {
        // Only the chip on the answer beat — it already reads "x = 10"; drawing
        // the bare value at the same anchor would double up during the fade.
        final t = (revealStep == scene.steps.length - 1)
            ? stepProgress.clamp(0.0, 1.0)
            : 1.0;
        _drawBadge(canvas, size, at, '${side.label} = ${_fmtLen(side.value)}', t);
      } else {
        _drawAngleValue(canvas, at, '${side.label} = ?', palette.highlightText, 1.0);
      }
    } else {
      final color = dimmed ? palette.dim : palette.text;
      final t = revealStep == 0 ? stepProgress.clamp(0.0, 1.0) : 1.0;
      _drawAngleValue(
          canvas, at, '${side.label} = ${_fmtLen(side.value)}', color, t);
    }
  }

  // ---- Base figure ----------------------------------------------------------

  void _paintBaseFigure(Canvas canvas, Offset Function(int) map, _Fit fit) {
    // The filled/outlined polygon (triangle, quadrilateral, n-gon).
    if (scene.polygonRing.length >= 3) {
      final path = Path();
      var started = false;
      for (final i in scene.polygonRing) {
        if (i < 0 || i >= scene.vertices.length) continue;
        final p = map(i);
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      if (started) {
        path.close();
        // For an AREA unknown the interior IS the answer: swell the fill on
        // the find-it beat (pulsing) and hold it strong once revealed.
        var fill = palette.figureFill;
        if (scene.unknownIsArea) {
          if (_focus == GeometryStepFocus.unknown) {
            final boost =
                1.0 + (1.2 + 0.8 * pulse) * stepProgress.clamp(0.0, 1.0);
            fill = fill.withValues(alpha: (fill.a * boost).clamp(0.0, 1.0));
          } else if (_answerRevealed) {
            final t = (revealStep == scene.steps.length - 1)
                ? stepProgress.clamp(0.0, 1.0)
                : 1.0;
            fill = fill.withValues(alpha: (fill.a * (1.0 + 2.0 * t)).clamp(0.0, 1.0));
          }
        }
        canvas.drawPath(path, Paint()..color = fill);
        canvas.drawPath(path, _stroke(palette.figureStroke, 2.5));
      }
    }

    // Optional circle outline (circle-theorem figures).
    final cc = scene.circleCenterVertex;
    final cr = scene.circleRadiusUnits;
    if (cc != null && cr != null && cc >= 0 && cc < scene.vertices.length) {
      final center = map(cc);
      // Convert the figure-space radius into pixels via the fit scale.
      final edge = fit.point(
        VisualPoint(scene.vertices[cc].x + cr, scene.vertices[cc].y),
      );
      final radiusPx = (edge - center).distance;
      if (radiusPx > 0 && radiusPx.isFinite) {
        canvas.drawCircle(center, radiusPx, _stroke(palette.figureStroke, 2.5));
      }
    }

    // Extra segments (rays, transversal, chords, radii).
    for (final seg in scene.segments) {
      if (seg.length < 2) continue;
      final a = seg[0], b = seg[1];
      if (a < 0 || a >= scene.vertices.length) continue;
      if (b < 0 || b >= scene.vertices.length) continue;
      canvas.drawLine(map(a), map(b), _stroke(palette.figureStroke, 2.2));
    }

    // Vertex dots + optional corner names.
    for (var i = 0; i < scene.vertices.length; i++) {
      // Skip the ray-fan origin duplicates and interior helper points cleanly:
      // only mark polygon corners, circle points, and named vertices.
      final named = scene.vertexLabels[i];
      final isCorner = scene.polygonRing.contains(i);
      if (isCorner || named != null) {
        canvas.drawCircle(map(i), 3.5, Paint()..color = palette.vertexDot);
      }
      if (named != null && named.isNotEmpty) {
        _labelOutside(canvas, map(i), named, palette.text);
      }
    }
  }

  void _paintTicks(Canvas canvas, Offset Function(int) map) {
    if (scene.polygonRing.length < 3) return;
    final ring = scene.polygonRing;
    for (final edge in scene.tickEdges) {
      if (edge < 0 || edge >= ring.length) continue;
      final a = ring[edge];
      final b = ring[(edge + 1) % ring.length];
      if (a >= scene.vertices.length || b >= scene.vertices.length) continue;
      _drawTicks(canvas, map(a), map(b), 1);
    }
  }

  void _drawTicks(Canvas canvas, Offset a, Offset b, int count) {
    final dir = _unit(b - a);
    if (dir == Offset.zero) return;
    final perp = Offset(-dir.dy, dir.dx);
    final mid = (a + b) / 2;
    final paint = _stroke(palette.tick, 2);
    const gap = 4.0, len = 5.0;
    final start = -(count - 1) / 2 * gap;
    for (var k = 0; k < count; k++) {
      final c = mid + dir * (start + k * gap);
      canvas.drawLine(c - perp * len, c + perp * len, paint);
    }
  }

  // ---- Angles ---------------------------------------------------------------

  void _paintAngle(
    Canvas canvas,
    Size size,
    Offset Function(int) map,
    GeometryAngle angle,
  ) {
    if (angle.vertex < 0 || angle.vertex >= scene.vertices.length) return;
    if (angle.ray1 < 0 || angle.ray1 >= scene.vertices.length) return;
    if (angle.ray2 < 0 || angle.ray2 >= scene.vertices.length) return;

    final v = map(angle.vertex);
    final p1 = map(angle.ray1);
    final p2 = map(angle.ray2);
    final d1 = _unit(p1 - v);
    final d2 = _unit(p2 - v);
    if (d1 == Offset.zero || d2 == Offset.zero) return;

    final focused = _highlighted.contains(angle.label);
    final dimmed = _highlighted.isNotEmpty && !focused;

    // Colour + emphasis. Focused angles glow with the pulse; the unknown always
    // uses the spotlight colour once we reach it.
    final Color base;
    if (angle.isUnknown) {
      base = palette.highlight;
    } else if (dimmed) {
      base = palette.dim;
    } else {
      base = palette.knownArc;
    }
    final glow = focused ? (0.5 + 0.5 * pulse) : 1.0;
    final arcColor = base.withValues(alpha: base.a * glow);
    final arcWidth = focused ? 3.2 : 2.2;

    // The known arcs sweep in on their step; otherwise they're complete.
    final sweepFraction = (!angle.isUnknown && revealStep == 0)
        ? stepProgress.clamp(0.0, 1.0)
        : 1.0;

    _drawArc(canvas, v, d1, d2, arcColor, arcWidth, sweepFraction);

    // Focus ring for the missing angle so the eye lands on it.
    if (angle.isUnknown && (_focus == GeometryStepFocus.unknown)) {
      _drawArc(
        canvas,
        v,
        d1,
        d2,
        palette.highlight.withValues(alpha: 0.25 + 0.35 * pulse),
        7.0,
        1.0,
      );
    }

    // Label at the bisector.
    final bis = _unit(d1 + d2);
    final labelDir = bis == Offset.zero ? const Offset(0, -1) : bis;
    final labelAt = v + labelDir * (_arcRadius + 14);

    if (angle.isUnknown) {
      if (_answerRevealed) {
        // Fade + scale the value in, then the badge.
        final t = (revealStep == scene.steps.length - 1)
            ? stepProgress.clamp(0.0, 1.0)
            : 1.0;
        _drawAngleValue(
            canvas, labelAt, '${_fmt(angle.value)}°', palette.highlightText, t);
        _drawAnswerBadge(canvas, size, map, angle, t);
      } else {
        _drawAngleValue(canvas, labelAt, '?', palette.highlightText, 1.0);
      }
    } else {
      final color = dimmed ? palette.dim : palette.text;
      final t = revealStep == 0 ? stepProgress.clamp(0.0, 1.0) : 1.0;
      _drawAngleValue(canvas, labelAt, '${_fmt(angle.value)}°', color, t);
    }
  }

  void _drawArc(
    Canvas canvas,
    Offset center,
    Offset d1,
    Offset d2,
    Color color,
    double width,
    double sweepFraction,
  ) {
    final start = d1.direction;
    var sweep = d2.direction - start;
    while (sweep <= -math.pi) {
      sweep += 2 * math.pi;
    }
    while (sweep > math.pi) {
      sweep -= 2 * math.pi;
    }
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: _arcRadius),
      start,
      sweep * sweepFraction.clamp(0.0, 1.0),
      false,
      _stroke(color, width),
    );
  }

  void _drawAngleValue(
    Canvas canvas,
    Offset at,
    String text,
    Color color,
    double opacity,
  ) {
    if (opacity <= 0.01) return;
    _drawText(
      canvas,
      at,
      text,
      AppTypography.caption.copyWith(
        color: color.withValues(alpha: color.a * opacity.clamp(0.0, 1.0)),
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
      center: true,
    );
  }

  /// The answer chip — "x = 80°" — stamped just outside the missing angle.
  void _drawAnswerBadge(
    Canvas canvas,
    Size size,
    Offset Function(int) map,
    GeometryAngle angle,
    double t,
  ) {
    final v = map(angle.vertex);
    final centroid = _centroid(map);
    final away = _unit(v - centroid);
    final dir = away == Offset.zero ? const Offset(0, -1) : away;
    _drawBadge(
        canvas, size, v + dir * 46, '${angle.label} = ${_fmt(angle.value)}°', t);
  }

  /// A rounded answer chip [text] near [anchor], scaling/fading in with [t] and
  /// clamped on-canvas. Shared by the angle and side reveals.
  void _drawBadge(
    Canvas canvas,
    Size size,
    Offset anchor,
    String text,
    double t,
  ) {
    if (t <= 0.01) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.caption.copyWith(
          color: palette.badgeText,
          fontWeight: FontWeight.w800,
          fontSize: 13,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const padX = 9.0, padY = 5.0;
    final w = tp.width + padX * 2;
    final h = tp.height + padY * 2;
    // Keep the chip on-canvas. Guard the clamp bounds: when the chip is wider
    // (or taller) than the canvas, `lower > upper` and `clamp` would throw —
    // centre it instead.
    final loX = w / 2 + 2, hiX = size.width - w / 2 - 2;
    final loY = h / 2 + 2, hiY = size.height - h / 2 - 2;
    final cx = hiX < loX ? size.width / 2 : anchor.dx.clamp(loX, hiX);
    final cy = hiY < loY ? size.height / 2 : anchor.dy.clamp(loY, hiY);
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);

    canvas.save();
    // Scale-in around the chip centre.
    final s = (0.7 + 0.3 * t).clamp(0.0, 1.0);
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(s);
    canvas.translate(-rect.center.dx, -rect.center.dy);

    final bg = palette.badgeBackground.withValues(
      alpha: palette.badgeBackground.a * t.clamp(0.0, 1.0),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(9)),
      Paint()..color = bg,
    );
    tp.paint(
      canvas,
      Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
    );
    canvas.restore();
  }

  // ---- Fit / mapping --------------------------------------------------------

  /// Uniform scale + centre + y-flip that fits the whole figure (including a
  /// circle's full extent) inside the canvas with padding.
  _Fit _computeFit(Size size) {
    final b = _bounds();
    final spanX = b.$2 - b.$1;
    final spanY = b.$4 - b.$3;
    final sx = spanX < 1e-9 ? double.infinity : (size.width - 2 * _pad) / spanX;
    final sy =
        spanY < 1e-9 ? double.infinity : (size.height - 2 * _pad) / spanY;
    var scale = math.min(sx, sy);
    if (!scale.isFinite || scale <= 0) scale = 1.0;
    final ox = (size.width - spanX * scale) / 2;
    final oy = (size.height - spanY * scale) / 2;
    return _Fit(
      minX: b.$1,
      minY: b.$3,
      scale: scale,
      ox: ox,
      oy: oy,
      height: size.height,
    );
  }

  /// (minX, maxX, minY, maxY) over the vertices, widened to include a circle.
  (double, double, double, double) _bounds() {
    if (scene.vertices.isEmpty) return (0, 1, 0, 1);
    var minX = scene.vertices.first.x, maxX = minX;
    var minY = scene.vertices.first.y, maxY = minY;
    for (final p in scene.vertices) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final cc = scene.circleCenterVertex;
    final cr = scene.circleRadiusUnits;
    if (cc != null && cr != null && cc >= 0 && cc < scene.vertices.length) {
      final c = scene.vertices[cc];
      minX = math.min(minX, c.x - cr);
      maxX = math.max(maxX, c.x + cr);
      minY = math.min(minY, c.y - cr);
      maxY = math.max(maxY, c.y + cr);
    }
    return (minX, maxX, minY, maxY);
  }

  Offset _centroid(Offset Function(int) map) {
    if (scene.vertices.isEmpty) return Offset.zero;
    var sum = Offset.zero;
    for (var i = 0; i < scene.vertices.length; i++) {
      sum += map(i);
    }
    return sum / scene.vertices.length.toDouble();
  }

  // ---- Text -----------------------------------------------------------------

  void _labelOutside(Canvas canvas, Offset at, String text, Color color) {
    _drawText(
      canvas,
      at + const Offset(6, -6),
      text,
      AppTypography.caption.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
    );
  }

  void _drawText(
    Canvas canvas,
    Offset at,
    String text,
    TextStyle style, {
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = center
        ? Offset(at.dx - tp.width / 2, at.dy - tp.height / 2)
        : at;
    tp.paint(canvas, origin);
  }

  // ---- Primitives -----------------------------------------------------------

  static Offset _unit(Offset o) {
    final d = o.distance;
    return d < 1e-6 ? Offset.zero : o / d;
  }

  Paint _stroke(Color color, double width) => Paint()
    ..color = color
    ..strokeWidth = width
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  String _fmt(double v) => GeometryScene.formatDegrees(v);

  String _fmtLen(double v) => GeometryScene.formatLength(v);

  @override
  bool shouldRepaint(GeometryScenePainter old) =>
      old.scene != scene ||
      old.revealStep != revealStep ||
      old.stepProgress != stepProgress ||
      old.pulse != pulse ||
      old.palette != palette;
}

/// An immutable figure-space → canvas mapping (uniform scale, centred, y up).
@immutable
class _Fit {
  const _Fit({
    required this.minX,
    required this.minY,
    required this.scale,
    required this.ox,
    required this.oy,
    required this.height,
  });

  final double minX, minY, scale, ox, oy, height;

  Offset point(VisualPoint p) => Offset(
        ox + (p.x - minX) * scale,
        height - oy - (p.y - minY) * scale,
      );
}
