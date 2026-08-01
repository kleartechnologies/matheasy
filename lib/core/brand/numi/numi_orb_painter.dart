import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'numi_spec.dart';

/// One rendered ripple ring.
typedef NumiRipple = ({double scale, double opacity});

/// One rendered sparkle.
typedef NumiSparkle = ({Offset center, double radius, double opacity});

/// Numi's animation resolved to a single moment in time.
///
/// This is a pure function of the clock — no tickers, no controllers — so the
/// whole motion system can be asserted directly in a unit test rather than
/// inferred from pixels. [NumiOrbPainter] only draws what this decides.
@immutable
class NumiFrame {
  const NumiFrame({
    required this.scale,
    required this.floatY,
    required this.coreOffset,
    required this.coreScale,
    required this.coreOpacity,
    required this.glowOpacity,
    required this.glowSpread,
    required this.ripples,
    required this.rippleColor,
    required this.sparkles,
  });

  /// `numi-breathe` — 1.000 at rest, up to the state's peak.
  final double scale;

  /// The float, in units of D. Negative is upward.
  final double floatY;

  /// `numi-core` — where the internal light has drifted to, in units of D.
  final Offset coreOffset;
  final double coreScale;
  final double coreOpacity;

  /// The final multiplier on the ambient glow's colours — the state's `--gs`,
  /// the size ramp and the ambient breath, combined. The surface is applied by
  /// the painter, which is the only part that knows where Numi is sitting.
  final double glowOpacity;

  /// …and how far the field has swelled with that breath.
  final double glowSpread;

  final List<NumiRipple> ripples;
  final Color rippleColor;
  final List<NumiSparkle> sparkles;

  /// The resting frame — what Numi looks like with motion switched off.
  ///
  /// Reduced motion must still show *Numi*, so this is the orb at 1.000 scale
  /// with its internal light at the position `numi-core` starts and ends on.
  /// No ripples, no sparkles: those exist only as motion.
  static NumiFrame still({double glowScale = 1.0}) => NumiFrame(
        scale: 1,
        floatY: 0,
        coreOffset: NumiSpec.coreDriftRest,
        coreScale: NumiSpec.coreScaleRest,
        coreOpacity: NumiSpec.coreOpacityRest,
        glowOpacity: glowScale * NumiSpec.glowOpacityRest,
        glowSpread: 1,
        ripples: const <NumiRipple>[],
        rippleColor: NumiSpec.highlight,
        sparkles: const <NumiSparkle>[],
      );

  /// How long the responding bloom holds before it starts settling (§05:
  /// "600ms · once").
  static const Duration respondBloom = Duration(milliseconds: 600);

  /// …and how long the return to idle takes. Long enough for the single
  /// 900 ms ring to finish expanding, so the gesture ends rather than snaps.
  static const Duration respondSettle = Duration(milliseconds: 900);

  /// Resolve the frame at [time] seconds on a free-running clock.
  ///
  /// [stateAge] is the time since this state was entered; only `responding`
  /// uses it, because it is the one state that happens *once* and then hands
  /// back to idle.
  static NumiFrame at({
    required double time,
    required NumiState state,
    double stateAge = 0,
    double glowScale = 1.0,
  }) {
    var spec = NumiStateSpec.of(state);
    if (state == NumiState.responding) {
      final bloom = respondBloom.inMilliseconds / 1000;
      final settle = respondSettle.inMilliseconds / 1000;
      final t = ((stateAge - bloom) / settle).clamp(0.0, 1.0);
      spec = spec.lerpTo(NumiStateSpec.idle, Curves.easeOut.transform(t));
    }

    final breathe = _pingPong(
      NumiSpec.breatheCurve,
      _phase(time, NumiSpec.breatheDuration),
    );
    final core = _pingPong(
      Curves.easeInOut,
      _phase(time, spec.coreDuration),
    );
    // `numi-ambient` shares the breathe's 6.5s clock but eases differently.
    final ambient = _pingPong(
      NumiSpec.glowCurve,
      _phase(time, NumiSpec.breatheDuration),
    );

    return NumiFrame(
      scale: 1 + (spec.scalePeak - 1) * breathe,
      floatY: NumiSpec.breatheFloat * breathe,
      coreOffset: Offset.lerp(
        NumiSpec.coreDriftRest,
        NumiSpec.coreDriftPeak,
        core,
      )!,
      coreScale: NumiSpec.coreScaleRest +
          (NumiSpec.coreScalePeak - NumiSpec.coreScaleRest) * core,
      coreOpacity: NumiSpec.coreOpacityRest +
          (NumiSpec.coreOpacityPeak - NumiSpec.coreOpacityRest) * core,
      glowOpacity: spec.glowScale *
          glowScale *
          (NumiSpec.glowOpacityRest +
              (NumiSpec.glowOpacityPeak - NumiSpec.glowOpacityRest) * ambient),
      glowSpread: 1 + (NumiSpec.glowSpreadPeak - 1) * ambient,
      rippleColor: spec.rippleColor,
      ripples: <NumiRipple>[
        for (final ring in spec.rings) _ripple(time, spec, ring),
      ].where((r) => r.opacity > 0).toList(growable: false),
      sparkles: <NumiSparkle>[
        for (final sparkle in NumiSpec.sparkles)
          _sparkle(time, spec.sparkleOpacity, sparkle),
      ].where((s) => s.opacity > 0).toList(growable: false),
    );
  }

  static NumiRipple _ripple(double time, NumiStateSpec spec, NumiRing ring) {
    final u = (_phase(time, spec.rippleDuration) + ring.phase) % 1.0;
    final e = NumiSpec.rippleCurve.transform(u);
    return (
      scale: 1 + (NumiSpec.rippleEndScale - 1) * e,
      opacity: NumiSpec.rippleStartOpacity *
          (1 - e) *
          ring.opacity *
          spec.rippleOpacity,
    );
  }

  static NumiSparkle _sparkle(
    double time,
    double layerOpacity,
    ({Offset center, double diameter, double phase}) sparkle,
  ) {
    final u = (_phase(time, NumiSpec.sparkleDuration) + sparkle.phase) % 1.0;
    const peak = NumiSpec.sparklePeak;
    final p = u < peak
        ? Curves.easeInOut.transform(u / peak)
        : 1 - Curves.easeInOut.transform((u - peak) / (1 - peak));
    final scale = NumiSpec.sparkleRestScale +
        (1 - NumiSpec.sparkleRestScale) * p;
    return (
      center: sparkle.center,
      radius: sparkle.diameter / 2 * scale,
      opacity: NumiSpec.sparklePeakOpacity * p * layerOpacity,
    );
  }

  static double _phase(double time, Duration period) =>
      (time / (period.inMicroseconds / Duration.microsecondsPerSecond)) % 1.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NumiFrame &&
          other.scale == scale &&
          other.floatY == floatY &&
          other.coreOffset == coreOffset &&
          other.coreScale == coreScale &&
          other.coreOpacity == coreOpacity &&
          other.glowOpacity == glowOpacity &&
          other.glowSpread == glowSpread &&
          other.rippleColor == rippleColor &&
          listEquals(other.ripples, ripples) &&
          listEquals(other.sparkles, sparkles);

  @override
  int get hashCode => Object.hash(
        scale,
        floatY,
        coreOffset,
        coreScale,
        coreOpacity,
        glowOpacity,
        glowSpread,
        rippleColor,
        Object.hashAll(ripples),
        Object.hashAll(sparkles),
      );

  /// A CSS keyframe that runs `0% → 50% → 100%` eases *into* the midpoint and
  /// back out of it, rather than easing once across the whole loop.
  static double _pingPong(Curve curve, double u) =>
      u < 0.5 ? curve.transform(u * 2) : 1 - curve.transform((u - 0.5) * 2);
}

/// Paints Numi: the green orb, the white four-point star and the soft glow.
///
/// Everything is derived from D (the orb diameter) and drawn with gradients and
/// paths, so it is resolution independent — there is no bitmap anywhere in the
/// mark. The glow deliberately paints **outside** the layout box, up to
/// 0.41 × D beyond the edge; §02 reserves 0.5 × D of clear space for exactly
/// this and calls the field "ambient, never clipped".
class NumiOrbPainter extends CustomPainter {
  const NumiOrbPainter({
    required this.frame,
    required this.starRatio,
    required this.surface,
  });

  final NumiFrame frame;

  /// The star's width as a fraction of D — 0.26 normally, larger when small.
  final double starRatio;

  final NumiSurface surface;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.shortestSide;
    if (d <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);

    // The ripples and the sparkles live in the field *around* Numi, outside
    // the breathing element — they hold still while it breathes. They are also
    // painted first, so the orb occludes whatever falls inside the disc and
    // only the sliver at its rim twinkles.
    _paintRipples(canvas, center, d);
    _paintSparkles(canvas, size, d);

    canvas.save();
    // `numi-breathe` — scale about the centre, then float.
    canvas.translate(center.dx, center.dy + frame.floatY * d);
    canvas.scale(frame.scale);
    canvas.translate(-center.dx, -center.dy);

    _paintGlow(canvas, center, d);

    // Everything from here is inside the orb: `overflow:hidden` on a circle.
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: d / 2)),
    );
    _paintBody(canvas, center, d);
    _paintCore(canvas, center, d);
    _paintBounce(canvas, center, d);
    _paintRim(canvas, center, d);
    _paintSpecular(canvas, center, d);
    _paintStarHalo(canvas, center, d);
    _paintStar(canvas, center, d);
    canvas.restore();

    canvas.restore();
  }

  // ── the ambient field ────────────────────────────────────────────────
  void _paintGlow(Canvas canvas, Offset center, double d) {
    // The multiplier is applied to the gradient's own alphas rather than to a
    // layer opacity: `--gs` runs past 1.0 (1.3 listening, 1.55 responding) and
    // a layer opacity would clamp there, flattening the very difference §05
    // describes as "+35%" and "+55% bloom".
    final opacity = frame.glowOpacity * surface.glowScale;
    if (opacity <= 0) return;
    final radius = NumiSpec.glowRadius * d * frame.glowSpread;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          _scaleAlpha(NumiSpec.glowColors, opacity),
          NumiSpec.glowStops,
        ),
    );
  }

  void _paintRipples(Canvas canvas, Offset center, double d) {
    for (final ripple in frame.ripples) {
      canvas.drawCircle(
        center,
        d / 2 * ripple.scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = NumiSpec.rippleStrokeWidth * ripple.scale
          ..color = frame.rippleColor.withValues(alpha: ripple.opacity),
      );
    }
  }

  void _paintSparkles(Canvas canvas, Size size, double d) {
    final origin = Offset(
      (size.width - d) / 2,
      (size.height - d) / 2,
    );
    for (final sparkle in frame.sparkles) {
      canvas.drawCircle(
        origin + sparkle.center * d,
        sparkle.radius * d,
        Paint()..color = Colors.white.withValues(alpha: sparkle.opacity),
      );
    }
  }

  // ── the sphere ───────────────────────────────────────────────────────
  void _paintBody(Canvas canvas, Offset center, double d) {
    final rect = Rect.fromCircle(center: center, radius: d / 2);
    // §06: on a brand-green surface the terminator deepens so the silhouette
    // still separates from the background.
    final colors = <Color>[
      ...NumiSpec.bodyColors.take(NumiSpec.bodyColors.length - 1),
      surface.shadowEdge,
    ];
    canvas.drawCircle(
      center,
      d / 2,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.topLeft + NumiSpec.bodyCenter * d,
          NumiSpec.bodyRadius * d,
          colors,
          NumiSpec.bodyStops,
        ),
    );
  }

  void _paintCore(Canvas canvas, Offset center, double d) {
    final rect = Rect.fromCircle(center: center, radius: d / 2);
    canvas.save();
    // transform: translate(…) scale(…) about the element's own centre.
    canvas.translate(frame.coreOffset.dx * d, frame.coreOffset.dy * d);
    canvas.translate(center.dx, center.dy);
    canvas.scale(frame.coreScale);
    canvas.translate(-center.dx, -center.dy);
    final origin = rect.topLeft + NumiSpec.coreCenter * d;
    final radius = NumiSpec.coreRadius * d;
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          origin,
          radius,
          _scaleAlpha(NumiSpec.coreColors, frame.coreOpacity),
          NumiSpec.coreStops,
        ),
    );
    canvas.restore();
  }

  void _paintBounce(Canvas canvas, Offset center, double d) {
    final rect = Rect.fromCircle(center: center, radius: d / 2);
    _ellipticalRadial(
      canvas,
      center: rect.topLeft + NumiSpec.bounceCenter * d,
      radiusX: NumiSpec.bounceRadiusX * d,
      radiusY: NumiSpec.bounceRadiusY * d,
      colors: NumiSpec.bounceColors,
      stops: NumiSpec.bounceStops,
    );
  }

  void _paintRim(Canvas canvas, Offset center, double d) {
    if (surface.rimOpacity <= 0) return;
    final radius = d / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          _scaleAlpha(NumiSpec.rimColors, surface.rimOpacity),
          NumiSpec.rimStops,
        ),
    );
  }

  void _paintSpecular(Canvas canvas, Offset center, double d) {
    final rect = Rect.fromCircle(center: center, radius: d / 2);
    _ellipticalRadial(
      canvas,
      center: rect.topLeft + NumiSpec.specularCenter * d,
      radiusX: NumiSpec.specularRadiusX * d,
      radiusY: NumiSpec.specularRadiusY * d,
      rotation: NumiSpec.specularRotation,
      colors: NumiSpec.specularColors,
      stops: NumiSpec.specularStops,
    );
  }

  // ── the signature ────────────────────────────────────────────────────
  void _paintStarHalo(Canvas canvas, Offset center, double d) {
    final rect = Rect.fromCircle(center: center, radius: d / 2);
    final origin = rect.topLeft + NumiSpec.starCenter * d;
    final radius = starRatio * NumiSpec.starHaloScale * d;
    canvas.drawCircle(
      origin,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          origin,
          radius,
          NumiSpec.starHaloColors,
          NumiSpec.starHaloStops,
        ),
    );
  }

  void _paintStar(Canvas canvas, Offset center, double d) {
    final rect = Rect.fromCircle(center: center, radius: d / 2);
    canvas.drawPath(
      numiStarPath(
        center: rect.topLeft + NumiSpec.starCenter * d,
        size: starRatio * d,
      ),
      Paint()..color = Colors.white,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────────
  void _ellipticalRadial(
    Canvas canvas, {
    required Offset center,
    required double radiusX,
    required double radiusY,
    required List<Color> colors,
    required List<double> stops,
    double rotation = 0,
  }) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (rotation != 0) canvas.rotate(rotation);
    canvas.scale(1, radiusY / radiusX);
    canvas.drawCircle(
      Offset.zero,
      radiusX,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          radiusX,
          colors,
          stops,
        ),
    );
    canvas.restore();
  }

  static List<Color> _scaleAlpha(List<Color> colors, double factor) => <Color>[
        for (final color in colors)
          color.withValues(alpha: (color.a * factor).clamp(0.0, 1.0)),
      ];

  @override
  bool shouldRepaint(NumiOrbPainter old) =>
      old.frame != frame ||
      old.starRatio != starRatio ||
      old.surface != surface;
}

/// The four-point star — §02: 4 points, inner ratio 0.30, **axis locked at 0°**.
///
/// [size] is the star's full width (its outer diameter), so it matches the
/// `starR × D` the design specifies. Exposed for tests and for any surface that
/// needs the signature on its own.
Path numiStarPath({required Offset center, required double size}) {
  final outer = size / 2;
  final inner = outer * NumiSpec.starInnerRatio;
  final path = Path();
  // Start at the top point and alternate outer/inner around the circle. The
  // first point sits at -90°, which is what locks the axis upright.
  const step = math.pi / NumiSpec.starPoints;
  for (var i = 0; i < NumiSpec.starPoints * 2; i++) {
    final radius = i.isEven ? outer : inner;
    final angle = -math.pi / 2 + i * step;
    final point =
        center + Offset(radius * math.cos(angle), radius * math.sin(angle));
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path..close();
}
