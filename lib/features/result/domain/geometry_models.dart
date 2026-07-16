import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'visual_models.dart' show VisualPoint;

/// GEOMETRY VISUAL LEARNING — the diagram-first, step-animated experience.
///
/// A [GeometryScene] is the deterministic, on-device model the geometry player
/// renders. It follows the same **golden rule** as the rest of the app: the
/// LLM never invents the arithmetic. The Visual Learning backend supplies only
/// the *given facts* of a geometry problem (the known angle measures, which one
/// is unknown, and the rule family); this layer then:
///
///   1. **computes the missing measure itself** (angle-sum rule, or an
///      equal / supplementary / complementary / double / half relation),
///   2. **constructs the figure from those numbers** so the drawing is correct
///      by construction (a 60-40-80 triangle is actually drawn 60-40-80), and
///   3. **synthesises the four canonical animation steps** (highlight the
///      knowns → show the rule → find the missing angle → stamp the answer).
///
/// Anything inconsistent (givens that don't leave a valid angle, or a computed
/// answer that disagrees with the solver's verified answer) makes
/// [GeometryScene.tryBuild] return `null`, and the Visual tab falls back to the
/// static concept explorer — it never shows a made-up diagram.

/// The geometry problem families the player understands. Each maps to a fixed
/// rule the app applies deterministically (see [GeometryScene.tryBuild]).
enum GeometrySceneKind {
  /// Interior angles of a triangle (sum 180°).
  triangleAngles,

  /// A triangle with two equal sides — base angles equal (sum 180°), drawn
  /// with congruence ticks on the equal sides.
  isoscelesTriangle,

  /// Interior angles of a quadrilateral (sum 360°).
  quadrilateralAngles,

  /// Interior angles of an n-gon (sum (n−2)·180°).
  polygonAngles,

  /// Angles on a straight line at a point (sum 180°).
  straightLineAngles,

  /// Angles around a point (sum 360°).
  anglesAroundPoint,

  /// Two parallel lines cut by a transversal — the unknown is derived from a
  /// known angle by an equal/supplementary [GeometryRelation].
  parallelLines,

  /// A circle angle relation (angle at the centre is twice the angle at the
  /// circumference, and its inverse) — [GeometryRelation.doubleOf]/`halfOf`.
  circleAngle,

  /// A right triangle where two SIDE LENGTHS are given and the third is found
  /// by Pythagoras (a² + b² = c²). Unlike the other kinds, the unknown is a
  /// length, not an angle.
  rightTrianglePythagoras,
}

/// How a [GeometryScene] is drawn. Kept separate from [GeometrySceneKind] so
/// several problem families can share one drawing primitive.
enum GeometryFigureKind {
  /// A closed polygon (triangle / quadrilateral / n-gon) plus its angle arcs.
  polygon,

  /// A fan of rays from a common vertex (straight line, angles around a point).
  rays,

  /// Two parallel lines cut by a transversal.
  parallelLines,

  /// A circle with radii and/or chords marking the angles.
  circle,
}

/// The relation that ties an unknown angle to a known reference (the non-sum
/// families). Sum families leave this `null`.
enum GeometryRelation {
  /// The unknown equals the reference (alternate / corresponding angles).
  equal,

  /// The unknown and the reference add to 180° (co-interior angles).
  supplementary,

  /// The unknown and the reference add to 90°.
  complementary,

  /// The unknown is twice the reference (angle at centre vs circumference).
  doubleOf,

  /// The unknown is half the reference (angle at circumference vs centre).
  halfOf,
}

/// One marked angle in a scene — a wedge at [vertex] between the rays toward
/// [ray1] and [ray2] (all indices into [GeometryScene.vertices]), carrying its
/// measure in degrees. Unknown angles start blank on the canvas and are filled
/// in only on the final reveal step.
@immutable
class GeometryAngle {
  const GeometryAngle({
    required this.label,
    required this.vertex,
    required this.ray1,
    required this.ray2,
    required this.value,
    this.isUnknown = false,
  });

  /// Display name, e.g. `A`, `x`, `∠BOC`.
  final String label;

  /// Index into [GeometryScene.vertices] of the angle's vertex.
  final int vertex;

  /// Index into [GeometryScene.vertices] of the first bounding ray's endpoint.
  final int ray1;

  /// Index into [GeometryScene.vertices] of the second bounding ray's endpoint.
  final int ray2;

  /// The measure in degrees (computed by the app, never the LLM).
  final double value;

  /// Whether this is the angle being solved for.
  final bool isUnknown;
}

/// A marked side length on the figure — an edge of [GeometryScene.polygonRing]
/// carrying a length label. Used by the Pythagoras scene (the unknown side is
/// blank until the answer beat).
@immutable
class GeometrySide {
  const GeometrySide({
    required this.label,
    required this.edge,
    required this.value,
    this.isUnknown = false,
  });

  /// Display name, e.g. `a`, `x`.
  final String label;

  /// Edge index into [GeometryScene.polygonRing] (vertex i → i+1).
  final int edge;

  /// The length (computed by the app for the unknown, never the LLM).
  final double value;

  /// Whether this is the side being solved for.
  final bool isUnknown;
}

/// The role of a side in a right triangle — which one is the hypotenuse.
enum GeometrySideRole { leg, hypotenuse }

/// A given side of a right-triangle Pythagoras problem: its label, its role,
/// and its length (`null` marks the single unknown).
@immutable
class GeometryKnownSide {
  const GeometryKnownSide({
    required this.label,
    required this.role,
    this.value,
  });

  final String label;
  final GeometrySideRole role;
  final double? value;
}

/// Which part of the walkthrough a [GeometryStep] represents — drives what the
/// painter highlights and reveals.
enum GeometryStepFocus {
  /// Highlight the given (known) angles.
  known,

  /// Show the rule / equation relating the angles.
  rule,

  /// Draw attention to the missing angle (still blank).
  unknown,

  /// Stamp the final answer directly on the diagram.
  answer,
}

/// One animation beat: what to say and what to emphasise. The [equationLatex]
/// is app-authored (delimiter-free) from the verified numbers.
@immutable
class GeometryStep {
  const GeometryStep({
    required this.focus,
    required this.title,
    required this.detail,
    this.equationLatex,
    this.highlight = const {},
  });

  final GeometryStepFocus focus;

  /// Short heading, e.g. "Angle sum rule".
  final String title;

  /// One student-friendly sentence.
  final String detail;

  /// The rule or rearrangement to show, as delimiter-free LaTeX (optional).
  final String? equationLatex;

  /// Angle labels to emphasise on the diagram for this step.
  final Set<String> highlight;

  /// Plain-language description for screen readers.
  String get semanticLabel => '$title. $detail';
}

/// The complete, solved, drawable geometry walkthrough.
@immutable
class GeometryScene {
  const GeometryScene({
    required this.kind,
    required this.figureKind,
    required this.vertices,
    required this.angles,
    required this.unknownLabel,
    required this.unknownValue,
    required this.ruleName,
    required this.caption,
    required this.semanticsLabel,
    required this.steps,
    this.sides = const [],
    this.unknownIsAngle = true,
    this.polygonRing = const [],
    this.segments = const [],
    this.tickEdges = const [],
    this.rightAngleVertices = const [],
    this.vertexLabels = const {},
    this.circleCenterVertex,
    this.circleRadiusUnits,
  });

  final GeometrySceneKind kind;
  final GeometryFigureKind figureKind;

  /// Figure-space points (auto-scaled + centred by the painter). Y is up.
  final List<VisualPoint> vertices;

  /// The marked angles (all knowns plus the single unknown). Empty for a
  /// length problem.
  final List<GeometryAngle> angles;

  /// The marked side lengths (all knowns plus the single unknown). Empty for an
  /// angle problem; populated for [GeometrySceneKind.rightTrianglePythagoras].
  final List<GeometrySide> sides;

  /// Whether the unknown is an ANGLE (degrees, `x = 80°`) or a LENGTH (`x = 8`).
  /// Controls answer formatting, the reveal text and screen-reader wording.
  final bool unknownIsAngle;

  /// The unknown's display label (e.g. `x`).
  final String unknownLabel;

  /// The unknown's computed measure — degrees for an angle, a length otherwise.
  final double unknownValue;

  /// Human name of the rule applied, e.g. "Angles in a triangle sum to 180°".
  final String ruleName;

  /// One-line legend shown under the diagram (also the accessible summary).
  final String caption;

  /// Full plain-text description for screen readers.
  final String semanticsLabel;

  /// The ordered animation steps (always the four canonical beats).
  final List<GeometryStep> steps;

  /// Vertex indices forming the filled/outlined closed shape (empty ⇒ none).
  final List<int> polygonRing;

  /// Extra line segments to draw, each a `[i, j]` index pair (rays, chords…).
  final List<List<int>> segments;

  /// Edge indices (into [polygonRing]) that carry congruence ticks.
  final List<int> tickEdges;

  /// Vertex indices carrying a right-angle mark.
  final List<int> rightAngleVertices;

  /// Optional corner names, keyed by vertex index.
  final Map<int, String> vertexLabels;

  /// When set, draw a circle outline centred on this vertex…
  final int? circleCenterVertex;

  /// …with this radius in figure units.
  final double? circleRadiusUnits;

  /// The unknown angle, or `null` if (defensively) none is marked unknown.
  GeometryAngle? get unknownAngle {
    for (final a in angles) {
      if (a.isUnknown) return a;
    }
    return null;
  }

  /// The unknown side, or `null` (angle scenes have none).
  GeometrySide? get unknownSide {
    for (final s in sides) {
      if (s.isUnknown) return s;
    }
    return null;
  }

  /// The unknown value formatted for display: degrees (integer/1dp) for angles,
  /// a length (integer/2dp) otherwise.
  String get unknownDisplay => unknownIsAngle
      ? formatDegrees(unknownValue)
      : formatLength(unknownValue);

  /// The final answer as delimiter-free LaTeX (`x = 80^\circ` or `x = 8`).
  String get answerLatex => unknownIsAngle
      ? '$unknownLabel = ${formatDegrees(unknownValue)}^\\circ'
      : '$unknownLabel = ${formatLength(unknownValue)}';

  /// A screen-reader description that matches the visual reveal at [stepIndex]:
  /// it names the givens and the rule throughout, but only states the answer on
  /// the answer beat — so it never spoils the walkthrough for VoiceOver users
  /// the way the full [semanticsLabel] would.
  String semanticsForStep(int stepIndex) {
    final revealed = stepIndex >= 0 &&
        stepIndex < steps.length &&
        steps[stepIndex].focus == GeometryStepFocus.answer;
    final noun = unknownIsAngle ? 'angle' : 'length';
    final givens = unknownIsAngle
        ? angles
            .where((a) => !a.isUnknown)
            .map((a) => '${a.label} equals ${formatDegrees(a.value)} degrees')
            .join(', ')
        : sides
            .where((s) => !s.isUnknown)
            .map((s) => '${s.label} equals ${formatLength(s.value)}')
            .join(', ');
    final answerText = unknownIsAngle
        ? 'The missing angle $unknownLabel is ${formatDegrees(unknownValue)} degrees.'
        : 'The missing length $unknownLabel is ${formatLength(unknownValue)}.';
    final buffer = StringBuffer('Geometry diagram. ');
    if (givens.isNotEmpty) buffer.write('Given $givens. ');
    if (ruleName.isNotEmpty) buffer.write('$ruleName. ');
    buffer.write(revealed ? answerText : 'Find the missing $noun $unknownLabel.');
    return buffer.toString();
  }

  /// Formats a degree value: whole numbers stay integers, else one decimal.
  static String formatDegrees(double value) {
    if ((value - value.roundToDouble()).abs() < 1e-6) {
      return '${value.round()}';
    }
    return value.toStringAsFixed(1);
  }

  /// Formats a length: whole numbers stay integers, else two decimals (a
  /// Pythagoras answer is often irrational, e.g. √136 ≈ 11.66).
  static String formatLength(double value) {
    if ((value - value.roundToDouble()).abs() < 1e-6) {
      return '${value.round()}';
    }
    return value.toStringAsFixed(2);
  }

  // ---- Construction ---------------------------------------------------------

  /// Builds a solved [GeometryScene] from the given facts, or returns `null`
  /// when the data is inconsistent, unsupported, or contradicts
  /// [expectedAnswerLatex] (the solver's verified answer, when known).
  ///
  /// This is the golden-rule gate for geometry: the unknown is computed here,
  /// never taken from the model.
  static GeometryScene? tryBuild({
    required GeometrySceneKind kind,
    required List<GeometryKnownAngle> knownAngles,
    required String unknownLabel,
    int? sides,
    GeometryRelation? relation,
    String? relationReference,
    String? ruleName,
    String? caption,
    String? expectedAnswerLatex,
  }) {
    final label = unknownLabel.trim().isEmpty ? 'x' : unknownLabel.trim();

    // Every given must be a real, positive, sub-360° angle.
    for (final k in knownAngles) {
      if (!k.value.isFinite || k.value <= 0 || k.value >= 360) return null;
    }

    final double unknownValue;
    final _ComputedRule computed;
    if (_isSumKind(kind)) {
      final result = _solveSum(kind, knownAngles, sides, label);
      if (result == null) return null;
      unknownValue = result.value;
      computed = result;
    } else {
      final result = _solveRelation(kind, knownAngles, relation, relationReference, label);
      if (result == null) return null;
      unknownValue = result.value;
      computed = result;
    }

    // A computed angle must itself be a valid, drawable measure.
    if (!unknownValue.isFinite || unknownValue <= 0 || unknownValue >= 360) {
      return null;
    }

    // Cross-check against the solver's verified answer, when we have one — never
    // show a diagram that disagrees with the Solution tab.
    final expected = _parseFirstNumber(expectedAnswerLatex);
    if (expected != null && (expected - unknownValue).abs() > 0.5) {
      return null;
    }

    final built = _buildFigure(kind, knownAngles, label, unknownValue, computed);
    if (built == null) return null;

    // Consistency gate (golden-rule safety net): every UNKNOWN wedge the figure
    // draws must carry exactly the measure the app computed. If a construction
    // ever draws a different number than the answer (e.g. a mishandled relation),
    // fall back to the generic explorer rather than render a figure that
    // contradicts itself. This backstops every kind, not just the one that
    // revealed it. (Isosceles apex-only legitimately marks BOTH base angles
    // unknown — several are fine, as long as they all agree.)
    final builtUnknowns = built.angles.where((a) => a.isUnknown).toList();
    if (builtUnknowns.isEmpty) return null;
    if (builtUnknowns.any((a) => (a.value - unknownValue).abs() > 0.5)) {
      return null;
    }

    final resolvedRule = (ruleName != null && ruleName.trim().isNotEmpty)
        ? ruleName.trim()
        : computed.ruleName;
    final resolvedCaption = (caption != null && caption.trim().isNotEmpty)
        ? caption.trim()
        : computed.ruleName;

    final steps = _buildSteps(
      knownAngles: knownAngles,
      unknownLabel: label,
      unknownValue: unknownValue,
      computed: computed,
    );

    final semantics = _semantics(knownAngles, label, unknownValue, resolvedRule);

    return GeometryScene(
      kind: kind,
      figureKind: built.figureKind,
      vertices: built.vertices,
      angles: built.angles,
      unknownLabel: label,
      unknownValue: unknownValue,
      ruleName: resolvedRule,
      caption: resolvedCaption,
      semanticsLabel: semantics,
      steps: steps,
      polygonRing: built.polygonRing,
      segments: built.segments,
      tickEdges: built.tickEdges,
      vertexLabels: built.vertexLabels,
      circleCenterVertex: built.circleCenterVertex,
      circleRadiusUnits: built.circleRadiusUnits,
    );
  }

  /// Builds a solved right-triangle **Pythagoras** scene from its given sides,
  /// or `null` when the data is inconsistent (doesn't form a real right
  /// triangle) or contradicts [expectedAnswerLatex]. The missing length is
  /// computed here — never taken from the model.
  static GeometryScene? tryBuildPythagoras({
    required List<GeometryKnownSide> sides,
    required String unknownLabel,
    String? ruleName,
    String? caption,
    String? expectedAnswerLatex,
  }) {
    // Exactly two known sides + one unknown, and exactly two legs + one
    // hypotenuse — anything else isn't a determinate right triangle.
    if (sides.length != 3) return null;
    final knownSides = sides.where((s) => s.value != null).toList();
    final unknowns = sides.where((s) => s.value == null).toList();
    if (knownSides.length != 2 || unknowns.length != 1) return null;
    final unknown = unknowns.first;
    // The label comes from the unknown SIDE so the figure, equations and answer
    // all agree; the param is only a fallback.
    final label = unknown.label.trim().isNotEmpty
        ? unknown.label.trim()
        : (unknownLabel.trim().isEmpty ? 'x' : unknownLabel.trim());
    for (final s in knownSides) {
      if (!s.value!.isFinite || s.value! <= 0) return null;
    }
    final legs = sides.where((s) => s.role == GeometrySideRole.leg).toList();
    final hyps =
        sides.where((s) => s.role == GeometrySideRole.hypotenuse).toList();
    if (legs.length != 2 || hyps.length != 1) return null;
    final hyp = hyps.first;

    // Compute the unknown length + the rule/rearrangement to show.
    final double unknownValue;
    final String ruleEq;
    final String rearrange;
    if (identical(unknown, hyp)) {
      // Unknown is the hypotenuse: c = √(a² + b²).
      final a = legs[0].value!, b = legs[1].value!;
      unknownValue = math.sqrt(a * a + b * b);
      ruleEq = '${legs[0].label}^2 + ${legs[1].label}^2 = $label^2';
      rearrange =
          '$label = \\sqrt{${formatLength(a)}^2 + ${formatLength(b)}^2}';
    } else {
      // Unknown is a leg: leg = √(c² − otherLeg²), needs c > otherLeg.
      final otherLeg = legs.firstWhere((s) => !identical(s, unknown));
      final c = hyp.value!, o = otherLeg.value!;
      if (c <= o) return null; // no real right triangle
      unknownValue = math.sqrt(c * c - o * o);
      ruleEq = '$label^2 + ${otherLeg.label}^2 = ${hyp.label}^2';
      rearrange =
          '$label = \\sqrt{${formatLength(c)}^2 - ${formatLength(o)}^2}';
    }
    if (!unknownValue.isFinite || unknownValue <= 0) return null;

    // Cross-check against the verified answer, when we have one.
    final expected = _parseFirstNumber(expectedAnswerLatex);
    if (expected != null && (expected - unknownValue).abs() > 0.5) return null;

    double sideLen(GeometryKnownSide s) =>
        identical(s, unknown) ? unknownValue : s.value!;

    // Right angle at C = (0,0); legs along +x and +y, so |CA|,|CB| are the legs
    // and |AB| the hypotenuse — correct by construction for either unknown.
    final legX = sideLen(legs[0]);
    final legY = sideLen(legs[1]);
    final vertices = <VisualPoint>[
      const VisualPoint(0, 0), // C (right angle) — index 0
      VisualPoint(legX, 0), // A — index 1
      VisualPoint(0, legY), // B — index 2
    ];

    GeometrySide toSide(GeometryKnownSide s, int edge) => GeometrySide(
          // The unknown side shows the resolved label so it matches the answer.
          label: identical(s, unknown) ? label : s.label,
          edge: edge,
          value: sideLen(s),
          isUnknown: identical(s, unknown),
        );
    // Edge 0: C→A (legs[0]); edge 1: A→B (hyp); edge 2: B→C (legs[1]).
    final builtSides = [
      toSide(legs[0], 0),
      toSide(hyp, 1),
      toSide(legs[1], 2),
    ];

    final resolvedRule = (ruleName != null && ruleName.trim().isNotEmpty)
        ? ruleName.trim()
        : "Pythagoras' theorem: a² + b² = c²";
    final resolvedCaption = (caption != null && caption.trim().isNotEmpty)
        ? caption.trim()
        : resolvedRule;

    final knownLabels = knownSides.map((s) => s.label).toSet();
    final knownText =
        knownSides.map((s) => '${s.label} = ${formatLength(s.value!)}').join(' and ');
    final steps = <GeometryStep>[
      GeometryStep(
        focus: GeometryStepFocus.known,
        title: 'Start with what we know',
        detail: 'The two sides given are $knownText.',
        highlight: knownLabels,
      ),
      GeometryStep(
        focus: GeometryStepFocus.rule,
        title: "Pythagoras' theorem",
        detail: 'In a right triangle, the squares of the two shorter sides add '
            'up to the square of the longest (the hypotenuse).',
        equationLatex: ruleEq,
        highlight: {...knownLabels, label},
      ),
      GeometryStep(
        focus: GeometryStepFocus.unknown,
        title: 'Find the missing side',
        detail: 'Rearrange for $label and take the square root.',
        equationLatex: rearrange,
        highlight: {label},
      ),
      GeometryStep(
        focus: GeometryStepFocus.answer,
        title: 'Answer',
        detail: 'The missing side is ${formatLength(unknownValue)}.',
        equationLatex: '$label = ${formatLength(unknownValue)}',
        highlight: {label},
      ),
    ];

    final semantics = 'Right triangle diagram. Given $knownText. '
        '$resolvedRule. The missing side $label is ${formatLength(unknownValue)}.';

    return GeometryScene(
      kind: GeometrySceneKind.rightTrianglePythagoras,
      figureKind: GeometryFigureKind.polygon,
      vertices: vertices,
      angles: const [],
      sides: builtSides,
      unknownIsAngle: false,
      unknownLabel: label,
      unknownValue: unknownValue,
      ruleName: resolvedRule,
      caption: resolvedCaption,
      semanticsLabel: semantics,
      steps: steps,
      polygonRing: const [0, 1, 2],
      rightAngleVertices: const [0],
    );
  }

  static bool _isSumKind(GeometrySceneKind kind) => switch (kind) {
        GeometrySceneKind.triangleAngles ||
        GeometrySceneKind.isoscelesTriangle ||
        GeometrySceneKind.quadrilateralAngles ||
        GeometrySceneKind.polygonAngles ||
        GeometrySceneKind.straightLineAngles ||
        GeometrySceneKind.anglesAroundPoint =>
          true,
        GeometrySceneKind.parallelLines ||
        GeometrySceneKind.circleAngle ||
        GeometrySceneKind.rightTrianglePythagoras =>
          false,
      };

  // ---- Sum-rule solving -----------------------------------------------------

  static _ComputedRule? _solveSum(
    GeometrySceneKind kind,
    List<GeometryKnownAngle> knowns,
    int? sides,
    String label,
  ) {
    if (knowns.isEmpty) return null;

    // Isosceles with only the apex given: the two equal base angles are the
    // shared unknown value ((180 − apex) / 2).
    if (kind == GeometrySceneKind.isoscelesTriangle && knowns.length == 1) {
      final apex = knowns.first.value;
      final base = (180 - apex) / 2;
      if (base <= 0) return null;
      return _ComputedRule(
        value: base,
        ruleName: 'Base angles of an isosceles triangle are equal',
        equationLatex:
            '${_deg(apex)} + $label + $label = ${_deg(180)}',
        rearrangedLatex:
            '$label = (${_deg(180)} - ${_deg(apex)}) \\div 2',
      );
    }

    final target = _sumTarget(kind, sides ?? (knowns.length + 1));
    if (target == null) return null;

    // For fixed-shape families the count must be exact so the answer is
    // determinate; open families (line / point) accept whatever fan was given.
    final expectedCount = _expectedAngleCount(kind, sides);
    if (expectedCount != null && knowns.length != expectedCount - 1) {
      return null;
    }

    var sumKnown = 0.0;
    for (final k in knowns) {
      sumKnown += k.value;
    }
    final value = target - sumKnown;

    final knownTerms = knowns.map((k) => _deg(k.value)).join(' + ');
    return _ComputedRule(
      value: value,
      ruleName: _sumRuleName(kind, sides ?? (knowns.length + 1), target),
      equationLatex: '$knownTerms + $label = ${_deg(target)}',
      rearrangedLatex:
          '$label = ${_deg(target)} - ${knowns.map((k) => _deg(k.value)).join(' - ')}',
    );
  }

  static double? _sumTarget(GeometrySceneKind kind, int sides) => switch (kind) {
        GeometrySceneKind.triangleAngles ||
        GeometrySceneKind.isoscelesTriangle ||
        GeometrySceneKind.straightLineAngles =>
          180,
        GeometrySceneKind.quadrilateralAngles ||
        GeometrySceneKind.anglesAroundPoint =>
          360,
        GeometrySceneKind.polygonAngles =>
          sides >= 3 && sides <= 20 ? (sides - 2) * 180.0 : null,
        GeometrySceneKind.parallelLines ||
        GeometrySceneKind.circleAngle ||
        GeometrySceneKind.rightTrianglePythagoras =>
          null,
      };

  static int? _expectedAngleCount(GeometrySceneKind kind, int? sides) =>
      switch (kind) {
        GeometrySceneKind.triangleAngles ||
        GeometrySceneKind.isoscelesTriangle =>
          3,
        GeometrySceneKind.quadrilateralAngles => 4,
        GeometrySceneKind.polygonAngles =>
          (sides != null && sides >= 3 && sides <= 20) ? sides : null,
        // Open fans: the number of angles is whatever the problem states.
        GeometrySceneKind.straightLineAngles ||
        GeometrySceneKind.anglesAroundPoint =>
          null,
        GeometrySceneKind.parallelLines ||
        GeometrySceneKind.circleAngle ||
        GeometrySceneKind.rightTrianglePythagoras =>
          null,
      };

  static String _sumRuleName(GeometrySceneKind kind, int sides, double target) =>
      switch (kind) {
        GeometrySceneKind.triangleAngles =>
          'Angles in a triangle sum to 180°',
        GeometrySceneKind.isoscelesTriangle =>
          'Angles in a triangle sum to 180°',
        GeometrySceneKind.quadrilateralAngles =>
          'Angles in a quadrilateral sum to 360°',
        GeometrySceneKind.polygonAngles =>
          'Interior angles of a ${_polygonName(sides)} sum to ${_deg(target).replaceAll('^\\circ', '')}°',
        GeometrySceneKind.straightLineAngles =>
          'Angles on a straight line sum to 180°',
        GeometrySceneKind.anglesAroundPoint =>
          'Angles around a point sum to 360°',
        GeometrySceneKind.parallelLines ||
        GeometrySceneKind.circleAngle ||
        GeometrySceneKind.rightTrianglePythagoras =>
          '',
      };

  static String _polygonName(int sides) => switch (sides) {
        3 => 'triangle',
        4 => 'quadrilateral',
        5 => 'pentagon',
        6 => 'hexagon',
        7 => 'heptagon',
        8 => 'octagon',
        _ => '$sides-gon',
      };

  // ---- Relation solving -----------------------------------------------------

  static _ComputedRule? _solveRelation(
    GeometrySceneKind kind,
    List<GeometryKnownAngle> knowns,
    GeometryRelation? relation,
    String? reference,
    String label,
  ) {
    if (relation == null || knowns.isEmpty) return null;

    // The reference is the named known, else the first known.
    GeometryKnownAngle ref = knowns.first;
    if (reference != null && reference.trim().isNotEmpty) {
      for (final k in knowns) {
        if (k.label == reference.trim()) {
          ref = k;
          break;
        }
      }
    }
    final r = ref.value;

    final double value;
    final String equation;
    final String rearranged;
    final String ruleName;
    switch (relation) {
      case GeometryRelation.equal:
        value = r;
        ruleName = kind == GeometrySceneKind.parallelLines
            ? 'Alternate angles are equal'
            : 'Angles in the same segment are equal';
        equation = '$label = ${ref.label}';
        rearranged = '$label = ${_deg(r)}';
      case GeometryRelation.supplementary:
        value = 180 - r;
        ruleName = 'Co-interior angles sum to 180°';
        equation = '${ref.label} + $label = ${_deg(180)}';
        rearranged = '$label = ${_deg(180)} - ${_deg(r)}';
      case GeometryRelation.complementary:
        value = 90 - r;
        ruleName = 'Complementary angles sum to 90°';
        equation = '${ref.label} + $label = ${_deg(90)}';
        rearranged = '$label = ${_deg(90)} - ${_deg(r)}';
      case GeometryRelation.doubleOf:
        value = 2 * r;
        ruleName = 'The angle at the centre is twice the angle at the circumference';
        equation = '$label = 2 \\times ${ref.label}';
        rearranged = '$label = 2 \\times ${_deg(r)}';
      case GeometryRelation.halfOf:
        value = r / 2;
        ruleName = 'The angle at the circumference is half the angle at the centre';
        equation = '$label = ${ref.label} \\div 2';
        rearranged = '$label = ${_deg(r)} \\div 2';
    }

    return _ComputedRule(
      value: value,
      ruleName: ruleName,
      equationLatex: equation,
      rearrangedLatex: rearranged,
      relation: relation,
      reference: ref,
    );
  }

  // ---- Figure construction --------------------------------------------------

  static _BuiltFigure? _buildFigure(
    GeometrySceneKind kind,
    List<GeometryKnownAngle> knowns,
    String label,
    double unknownValue,
    _ComputedRule computed,
  ) {
    switch (kind) {
      case GeometrySceneKind.triangleAngles:
      case GeometrySceneKind.isoscelesTriangle:
        return _buildTriangle(kind, knowns, label, unknownValue);
      case GeometrySceneKind.quadrilateralAngles:
      case GeometrySceneKind.polygonAngles:
        return _buildPolygon(knowns, label, unknownValue);
      case GeometrySceneKind.straightLineAngles:
        return _buildRayFan(knowns, label, unknownValue, totalDegrees: 180);
      case GeometrySceneKind.anglesAroundPoint:
        return _buildRayFan(knowns, label, unknownValue, totalDegrees: 360);
      case GeometrySceneKind.parallelLines:
        return _buildParallelLines(knowns, label, unknownValue, computed);
      case GeometrySceneKind.circleAngle:
        return _buildCircle(knowns, label, unknownValue, computed);
      case GeometrySceneKind.rightTrianglePythagoras:
        // Pythagoras is length-based and built via [tryBuildPythagoras], never
        // through the angle path — unreachable here.
        return null;
    }
  }

  /// Exact triangle from its three interior angles (law of sines, unit base).
  static _BuiltFigure? _buildTriangle(
    GeometrySceneKind kind,
    List<GeometryKnownAngle> knowns,
    String label,
    double unknownValue,
  ) {
    // Resolve the three interior angles (A, B, C) and which is unknown.
    final List<_Slot> slots;
    if (kind == GeometrySceneKind.isoscelesTriangle && knowns.length == 1) {
      // Apex known at A; equal base angles (the unknown) at B and C.
      slots = [
        _Slot(knowns.first.label, knowns.first.value, false),
        _Slot(label, unknownValue, true),
        _Slot(label, unknownValue, true),
      ];
    } else {
      if (knowns.length != 2) return null;
      slots = [
        _Slot(knowns[0].label, knowns[0].value, false),
        _Slot(knowns[1].label, knowns[1].value, false),
        _Slot(label, unknownValue, true),
      ];
    }

    final a = slots[0].value; // angle at A
    final b = slots[1].value; // angle at B
    final c = slots[2].value; // angle at C
    if (a <= 0 || b <= 0 || c <= 0) return null;
    final sinC = math.sin(_rad(c));
    if (sinC.abs() < 1e-6) return null;

    // Base AB = 1 along the x-axis (A at the origin); C found from A's angle
    // and side AC (opposite B), by the law of sines.
    final ac = math.sin(_rad(b)) / sinC; // side b (opposite B) with AB(c)=1
    final cx = ac * math.cos(_rad(a));
    final cy = ac * math.sin(_rad(a));
    final vertices = [
      const VisualPoint(0, 0),
      const VisualPoint(1, 0),
      VisualPoint(cx, cy),
    ];

    final angles = [
      GeometryAngle(
        label: slots[0].label,
        vertex: 0,
        ray1: 1,
        ray2: 2,
        value: a,
        isUnknown: slots[0].isUnknown,
      ),
      GeometryAngle(
        label: slots[1].label,
        vertex: 1,
        ray1: 2,
        ray2: 0,
        value: b,
        isUnknown: slots[1].isUnknown,
      ),
      GeometryAngle(
        label: slots[2].label,
        vertex: 2,
        ray1: 0,
        ray2: 1,
        value: c,
        isUnknown: slots[2].isUnknown,
      ),
    ];

    // Isosceles: mark the two equal sides. Apex-known case ⇒ the equal sides
    // are AB (edge 0) and CA (edge 2), which meet the equal base angles.
    final tickEdges = <int>[];
    if (kind == GeometrySceneKind.isoscelesTriangle) {
      if (knowns.length == 1) {
        tickEdges.addAll([0, 2]); // legs from the apex A
      }
    }

    return _BuiltFigure(
      figureKind: GeometryFigureKind.polygon,
      vertices: vertices,
      angles: angles,
      polygonRing: const [0, 1, 2],
      tickEdges: tickEdges,
    );
  }

  /// Canonical regular n-gon with the true angle values labelled at each corner.
  static _BuiltFigure? _buildPolygon(
    List<GeometryKnownAngle> knowns,
    String label,
    double unknownValue,
  ) {
    final n = knowns.length + 1;
    if (n < 3 || n > 20) return null;

    // Regular-polygon corner positions (visually clean; the labels carry the
    // real measures — a general polygon isn't determined by its angles alone).
    final vertices = <VisualPoint>[];
    for (var i = 0; i < n; i++) {
      final t = math.pi / 2 + 2 * math.pi * i / n; // start at the top, go CCW
      vertices.add(VisualPoint(math.cos(t), math.sin(t)));
    }

    // The unknown occupies the last corner; the knowns fill the rest in order.
    final angles = <GeometryAngle>[];
    for (var i = 0; i < n; i++) {
      final prev = (i - 1 + n) % n;
      final next = (i + 1) % n;
      final isUnknown = i == n - 1;
      angles.add(GeometryAngle(
        label: isUnknown ? label : knowns[i].label,
        vertex: i,
        ray1: prev,
        ray2: next,
        value: isUnknown ? unknownValue : knowns[i].value,
        isUnknown: isUnknown,
      ));
    }

    return _BuiltFigure(
      figureKind: GeometryFigureKind.polygon,
      vertices: vertices,
      angles: angles,
      polygonRing: [for (var i = 0; i < n; i++) i],
    );
  }

  /// A fan of rays whose consecutive gaps are the given angles. For a straight
  /// line the fan spans 180°; around a point, 360°.
  static _BuiltFigure? _buildRayFan(
    List<GeometryKnownAngle> knowns,
    String label,
    double unknownValue, {
    required double totalDegrees,
  }) {
    // The angle gaps in order: knowns first, unknown last.
    final gaps = <_Slot>[
      for (final k in knowns) _Slot(k.label, k.value, false),
      _Slot(label, unknownValue, true),
    ];
    if (gaps.length < 2) return null;

    final closed = totalDegrees >= 359.999; // around a point wraps
    final tipCount = closed ? gaps.length : gaps.length + 1;

    // Cumulative boundary directions. Straight line: 0°(right) … 180°(left).
    final vertices = <VisualPoint>[const VisualPoint(0, 0)]; // O at index 0
    var acc = 0.0;
    for (var i = 0; i < tipCount; i++) {
      final t = _rad(acc);
      vertices.add(VisualPoint(math.cos(t), math.sin(t)));
      if (i < gaps.length) acc += gaps[i].value;
    }

    final angles = <GeometryAngle>[];
    for (var i = 0; i < gaps.length; i++) {
      final r1 = i + 1; // tip i
      final r2 = closed ? ((i + 1) % gaps.length) + 1 : i + 2; // next tip (wrap)
      angles.add(GeometryAngle(
        label: gaps[i].label,
        vertex: 0,
        ray1: r1,
        ray2: r2,
        value: gaps[i].value,
        isUnknown: gaps[i].isUnknown,
      ));
    }

    // Draw every ray from O.
    final segments = <List<int>>[
      for (var i = 1; i < vertices.length; i++) [0, i],
    ];

    return _BuiltFigure(
      figureKind: GeometryFigureKind.rays,
      vertices: vertices,
      angles: angles,
      segments: segments,
    );
  }

  /// Two parallel lines cut by a transversal whose slope equals the reference
  /// angle, so the drawn angle matches its label.
  static _BuiltFigure? _buildParallelLines(
    List<GeometryKnownAngle> knowns,
    String label,
    double unknownValue,
    _ComputedRule computed,
  ) {
    final ref = computed.reference ?? (knowns.isNotEmpty ? knowns.first : null);
    if (ref == null) return null;
    // Draw the transversal at the reference angle (clamped to stay legible).
    final phi = _rad(ref.value.clamp(20, 160).toDouble());
    final dir = VisualPoint(math.cos(phi), math.sin(phi));

    // Two horizontal lines y = ±1; transversal through the origin.
    const topY = 1.0, botY = -1.0;
    // Parametrise the transversal p = t·dir; find where it meets each line.
    if (dir.y.abs() < 1e-6) return null;
    final tTop = topY / dir.y;
    final tBot = botY / dir.y;
    final pTop = VisualPoint(tTop * dir.x, topY); // vertex 0
    final pBot = VisualPoint(tBot * dir.x, botY); // vertex 1

    // Line endpoints (extend well past the intersections).
    const half = 2.2;
    final topL = VisualPoint(pTop.x - half, topY); // 2
    final topR = VisualPoint(pTop.x + half, topY); // 3
    final botL = VisualPoint(pBot.x - half, botY); // 4
    final botR = VisualPoint(pBot.x + half, botY); // 5
    // Transversal ends.
    final trUp = VisualPoint(pTop.x + dir.x * 1.4, topY + dir.y * 1.4); // 6
    final trDn = VisualPoint(pBot.x - dir.x * 1.4, botY - dir.y * 1.4); // 7

    final vertices = [pTop, pBot, topL, topR, botL, botR, trUp, trDn];

    // Known angle at the top intersection between the line (right) and the
    // transversal going up.
    final knownAngle = GeometryAngle(
      label: ref.label,
      vertex: 0,
      ray1: 3, // topR
      ray2: 6, // trUp
      value: ref.value,
    );
    // Unknown at the bottom intersection, measured against the transversal going
    // DOWN (trDn, index 7) so the drawn arc opens to the labelled value:
    //   alternate (equal): between the line-left and trDn  ⇒ opens to φ (the Z);
    //   co-interior (supp.): between the line-right and trDn ⇒ opens to 180−φ.
    // (Using trUp/pTop here would draw the supplement of each, contradicting the
    // label — the number is right, but the picture would lie.)
    final isEqual = computed.relation == GeometryRelation.equal;
    final unknownAngle = GeometryAngle(
      label: label,
      vertex: 1,
      ray1: isEqual ? 4 : 5, // botL for alternate, botR for co-interior
      ray2: 7, // trDn — transversal going down from pBot
      value: unknownValue,
      isUnknown: true,
    );

    return _BuiltFigure(
      figureKind: GeometryFigureKind.parallelLines,
      vertices: vertices,
      angles: [knownAngle, unknownAngle],
      segments: [
        [2, 3], // top line
        [4, 5], // bottom line
        [6, 7], // transversal
      ],
    );
  }

  /// A circle with a central angle and an inscribed angle subtending the same
  /// chord — for the centre/circumference relation.
  static _BuiltFigure? _buildCircle(
    List<GeometryKnownAngle> knowns,
    String label,
    double unknownValue,
    _ComputedRule computed,
  ) {
    // This construction only draws the centre/circumference relation. Other
    // circle relations (e.g. same-segment `equal`) need a different figure, so
    // bail to the generic explorer rather than mis-draw one.
    final relation = computed.relation;
    if (relation != GeometryRelation.doubleOf &&
        relation != GeometryRelation.halfOf) {
      return null;
    }

    // Resolve the two measures: central (γ) and inscribed (γ/2).
    final double central;
    final bool centralIsUnknown;
    if (relation == GeometryRelation.doubleOf) {
      // Unknown = centre = 2 × known(circumference).
      central = unknownValue;
      centralIsUnknown = true;
    } else {
      // halfOf: unknown = circumference = known(centre) / 2.
      central = (computed.reference ?? knowns.first).value;
      centralIsUnknown = false;
    }
    // A reflex central angle can't be drawn faithfully (the arc would show its
    // non-reflex supplement while the label says the reflex value) — fall back.
    if (central <= 0 || central > 180) return null;

    // Points A and B on the circle, symmetric about the top; P at the bottom.
    final half = _rad(central / 2);
    final a = VisualPoint(math.sin(half), math.cos(half)); // upper right area
    final b = VisualPoint(-math.sin(half), math.cos(half)); // upper left
    const o = VisualPoint(0, 0); // centre — index 0
    const p = VisualPoint(0, -1); // on the circle (bottom) — index 3
    final vertices = [o, a, b, p];

    final centreLabel = centralIsUnknown ? label : (computed.reference?.label ?? 'AOB');
    final circLabel = centralIsUnknown ? (computed.reference?.label ?? knowns.first.label) : label;

    final centreAngle = GeometryAngle(
      label: centreLabel,
      vertex: 0,
      ray1: 1,
      ray2: 2,
      value: central,
      isUnknown: centralIsUnknown,
    );
    final inscribedAngle = GeometryAngle(
      label: circLabel,
      vertex: 3,
      ray1: 1,
      ray2: 2,
      value: central / 2,
      isUnknown: !centralIsUnknown,
    );

    return _BuiltFigure(
      figureKind: GeometryFigureKind.circle,
      vertices: vertices,
      angles: [centreAngle, inscribedAngle],
      segments: [
        [0, 1], // radius OA
        [0, 2], // radius OB
        [3, 1], // chord PA
        [3, 2], // chord PB
      ],
      circleCenterVertex: 0,
      circleRadiusUnits: 1,
      vertexLabels: {1: 'A', 2: 'B', 3: 'P', 0: 'O'},
    );
  }

  // ---- Step synthesis -------------------------------------------------------

  static List<GeometryStep> _buildSteps({
    required List<GeometryKnownAngle> knownAngles,
    required String unknownLabel,
    required double unknownValue,
    required _ComputedRule computed,
  }) {
    final knownLabels = knownAngles.map((k) => k.label).toSet();
    final knownText = knownAngles.map((k) => _degPlain(k.value)).join(' and ');
    final answerLatex = '$unknownLabel = ${_deg(unknownValue)}';

    return [
      GeometryStep(
        focus: GeometryStepFocus.known,
        title: 'Start with what we know',
        detail: knownAngles.length == 1
            ? 'One angle is given: $knownText.'
            : 'The angles given are $knownText.',
        highlight: knownLabels,
      ),
      GeometryStep(
        focus: GeometryStepFocus.rule,
        title: 'Use the rule',
        detail: computed.ruleName.endsWith('.')
            ? computed.ruleName
            : '${computed.ruleName}.',
        equationLatex: computed.equationLatex,
        highlight: {...knownLabels, unknownLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.unknown,
        title: 'Find the missing angle',
        detail: 'Rearrange to leave $unknownLabel on its own.',
        equationLatex: computed.rearrangedLatex,
        highlight: {unknownLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.answer,
        title: 'Answer',
        detail: 'The missing angle is ${_degPlain(unknownValue)}.',
        equationLatex: answerLatex,
        highlight: {unknownLabel},
      ),
    ];
  }

  static String _semantics(
    List<GeometryKnownAngle> knowns,
    String label,
    double value,
    String rule,
  ) {
    final givens = knowns.map((k) => '${k.label} equals ${_degPlain(k.value)}').join(', ');
    return 'Geometry diagram. Given $givens. $rule. '
        'The missing angle $label is ${_degPlain(value)}.';
  }

  // ---- Small helpers --------------------------------------------------------

  static double _rad(double deg) => deg * math.pi / 180;

  /// Delimiter-free LaTeX for a degree value, e.g. `80^\circ`.
  static String _deg(double value) => '${formatDegrees(value)}^\\circ';

  /// Plain-text degree value for prose/semantics, e.g. `80°`.
  static String _degPlain(double value) => '${formatDegrees(value)}°';

  /// Extracts the first signed decimal number from a string (the solver's
  /// answer often looks like `x = 80^\circ` or `80`).
  static double? _parseFirstNumber(String? source) {
    if (source == null) return null;
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(source);
    if (match == null) return null;
    return double.tryParse(match.group(0)!);
  }
}

/// A given angle: its display label and measure in degrees.
@immutable
class GeometryKnownAngle {
  const GeometryKnownAngle({required this.label, required this.value});

  final String label;
  final double value;
}

// ---- Internal construction records ------------------------------------------

@immutable
class _Slot {
  const _Slot(this.label, this.value, this.isUnknown);
  final String label;
  final double value;
  final bool isUnknown;
}

@immutable
class _ComputedRule {
  const _ComputedRule({
    required this.value,
    required this.ruleName,
    required this.equationLatex,
    required this.rearrangedLatex,
    this.relation,
    this.reference,
  });

  final double value;
  final String ruleName;

  /// The rule as an equation with the unknown still in it, e.g.
  /// `60^\circ + 40^\circ + x = 180^\circ`.
  final String equationLatex;

  /// The same rule rearranged for the unknown, e.g.
  /// `x = 180^\circ - 60^\circ - 40^\circ`.
  final String rearrangedLatex;
  final GeometryRelation? relation;
  final GeometryKnownAngle? reference;
}

@immutable
class _BuiltFigure {
  const _BuiltFigure({
    required this.figureKind,
    required this.vertices,
    required this.angles,
    this.polygonRing = const [],
    this.segments = const [],
    this.tickEdges = const [],
    this.vertexLabels = const {},
    this.circleCenterVertex,
    this.circleRadiusUnits,
  });

  final GeometryFigureKind figureKind;
  final List<VisualPoint> vertices;
  final List<GeometryAngle> angles;
  final List<int> polygonRing;
  final List<List<int>> segments;
  final List<int> tickEdges;
  final Map<int, String> vertexLabels;
  final int? circleCenterVertex;
  final double? circleRadiusUnits;
}
