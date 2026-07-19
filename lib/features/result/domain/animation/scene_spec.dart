import 'package:flutter/material.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the deterministic "visual object" that
/// accompanies a walkthrough (a balance scale, a parabola, a pie, a fraction
/// bar …). Exactly ONE [SceneObject] rides on an [AnimationScript]; the player
/// reveals it beat-by-beat alongside the equation morph, like the geometry
/// player reveals its figure.
///
/// Golden rule: every number in [params]/[points] is placed by an on-device
/// SceneBuilder from the *verified* solve — the LLM never fills these.

/// The drawable kinds the animated primitive painters understand. Unknown →
/// [none] (the player shows the morph only), so this can grow safely.
enum SceneObjectKind {
  /// Two-pan balance for a linear equation (`balance_scale_painter`).
  balanceScale,

  /// Partitioned fraction bar(s).
  fractionBar,

  /// A pie / proportion wheel.
  pieChart,

  /// Vertical bars (data).
  barChart,

  /// A multiplication / factoring area grid.
  areaModel,

  /// A number line with a marked value or interval.
  numberLine,

  /// A parabola `y = a x^2 + b x + c` with its roots.
  parabola,

  /// A sampled function curve (from the verified graph samples).
  curve,

  /// A curve with a sweeping tangent line (derivative).
  tangent,

  /// A curve filled with Riemann rectangles (integral).
  riemann,

  /// The unit circle with a marked angle.
  unitCircle,

  /// A probability tree.
  treeDiagram,

  /// A grid of matrix cells.
  matrixGrid,

  /// Vector arrows on axes.
  vectors,

  /// No visual object — render the equation morph alone.
  none,
}

/// A deterministically-built visual object. Deliberately loose (kind + numeric
/// params + display labels + points) so a builder can describe any drawing
/// without a schema change, and malformed data degrades to [SceneObjectKind.none].
@immutable
class SceneObject {
  const SceneObject({
    required this.kind,
    this.caption = '',
    this.params = const {},
    this.labels = const {},
    this.points = const [],
  });

  /// The empty object — nothing drawable.
  static const SceneObject none = SceneObject(kind: SceneObjectKind.none);

  final SceneObjectKind kind;

  /// One-line description (also the accessible label announced in place of the
  /// canvas).
  final String caption;

  /// Named numeric parameters, e.g. `{'a': 1, 'b': -5, 'c': 6}`.
  final Map<String, double> params;

  /// Named display strings, e.g. side chips, axis titles, bar names.
  final Map<String, String> labels;

  /// Point-driven data (bars, curve samples, vector components).
  final List<Offset> points;

  bool get isDrawable => kind != SceneObjectKind.none;

  /// Reads a named parameter with a safe default.
  double param(String name, {double fallback = 0}) =>
      params[name] ?? fallback;
}
