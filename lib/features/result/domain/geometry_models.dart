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

  /// A right triangle where ONE side and ONE acute angle are given and another
  /// side is found by a trig ratio (SOH CAH TOA). The unknown is a length.
  rightTriangleTrig,

  /// Any triangle where two sides and a NON-included angle are given and the
  /// angle opposite the other given side is found by the sine rule — including
  /// the ambiguous (acute/obtuse) case, disambiguated by the problem's own
  /// wording ([AngleBranchHint]), never by guessing.
  sineRuleAngle,

  /// Triangle area from two sides and the INCLUDED angle between them:
  /// Area = ½·a·b·sin C. The unknown is an area (not drawn as a blank mark —
  /// the whole interior is the answer).
  sasArea,
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

/// A side's position RELATIVE TO the known acute angle of a right triangle:
/// across from it, touching it (the leg), or across from the right angle.
enum GeometryTrigSideRole { opposite, adjacent, hypotenuse }

/// A side of a right-triangle trig problem: its label, its role relative to
/// the known angle, and its length (`null` marks the single unknown).
@immutable
class GeometryTrigSide {
  const GeometryTrigSide({
    required this.label,
    required this.role,
    this.value,
  });

  final String label;
  final GeometryTrigSideRole role;
  final double? value;
}

/// Which sine-rule branch the PROBLEM ITSELF selects ("angle y is obtuse").
/// This never supplies a number — it only picks between two app-computed
/// candidates; with no hint and both branches valid, the scene refuses to
/// guess and returns null (golden rule).
enum AngleBranchHint { acute, obtuse }

/// What kind of quantity the scene's unknown is — drives answer formatting,
/// reveal text and screen-reader wording.
enum GeometryUnknownKind { angle, length, area }

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
    this.unknownKind = GeometryUnknownKind.angle,
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

  /// Whether the unknown is an ANGLE (degrees, `x = 80°`), a LENGTH (`x = 8`)
  /// or an AREA (`Area = 45`). Controls answer formatting, the reveal text and
  /// screen-reader wording.
  final GeometryUnknownKind unknownKind;

  /// Back-compat convenience: true when the unknown is an angle.
  bool get unknownIsAngle => unknownKind == GeometryUnknownKind.angle;

  /// True when the unknown is the triangle's area (no blank mark on the
  /// figure — the whole interior is the answer, so the painter emphasises the
  /// fill and stamps the badge at the centroid).
  bool get unknownIsArea => unknownKind == GeometryUnknownKind.area;

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
  /// a length/area (integer/2dp) otherwise.
  String get unknownDisplay => unknownIsAngle
      ? formatDegrees(unknownValue)
      : formatLength(unknownValue);

  /// The unknown's label as delimiter-free LaTeX — a word label ("Area") is
  /// wrapped in `\text{}` so it doesn't render as a variable product.
  String get _labelLatex =>
      unknownLabel.length > 1 ? '\\text{$unknownLabel}' : unknownLabel;

  /// The final answer as delimiter-free LaTeX
  /// (`x = 80^\circ`, `x = 8`, or `\text{Area} = 45`).
  String get answerLatex => switch (unknownKind) {
        GeometryUnknownKind.angle =>
          '$unknownLabel = ${formatDegrees(unknownValue)}^\\circ',
        GeometryUnknownKind.length =>
          '$unknownLabel = ${formatLength(unknownValue)}',
        GeometryUnknownKind.area =>
          '$_labelLatex = ${formatLength(unknownValue)}',
      };

  /// A screen-reader description that matches the visual reveal at [stepIndex]:
  /// it names the givens and the rule throughout, but only states the answer on
  /// the answer beat — so it never spoils the walkthrough for VoiceOver users
  /// the way the full [semanticsLabel] would.
  String semanticsForStep(int stepIndex) {
    final revealed = stepIndex >= 0 &&
        stepIndex < steps.length &&
        steps[stepIndex].focus == GeometryStepFocus.answer;
    final noun = switch (unknownKind) {
      GeometryUnknownKind.angle => 'angle',
      GeometryUnknownKind.length => 'length',
      GeometryUnknownKind.area => 'area',
    };
    // Mixed-given scenes (trig / sine rule / area) carry BOTH known angles and
    // known sides — list every given, whatever it is.
    final givens = [
      ...angles
          .where((a) => !a.isUnknown)
          .map((a) => '${a.label} equals ${formatDegrees(a.value)} degrees'),
      ...sides
          .where((s) => !s.isUnknown)
          .map((s) => '${s.label} equals ${formatLength(s.value)}'),
    ].join(', ');
    final answerText = switch (unknownKind) {
      GeometryUnknownKind.angle =>
        'The missing angle $unknownLabel is ${formatDegrees(unknownValue)} degrees.',
      GeometryUnknownKind.length =>
        'The missing length $unknownLabel is ${formatLength(unknownValue)}.',
      GeometryUnknownKind.area =>
        'The area is ${formatLength(unknownValue)}.',
    };
    final buffer = StringBuffer('Geometry diagram. ');
    if (givens.isNotEmpty) buffer.write('Given $givens. ');
    if (ruleName.isNotEmpty) buffer.write('$ruleName. ');
    buffer.write(revealed
        ? answerText
        : unknownIsArea
            ? 'Find the area of the triangle.'
            : 'Find the missing $noun $unknownLabel.');
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
    final expected = _parseExpectedValue(expectedAnswerLatex);
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
    final expected = _parseExpectedValue(expectedAnswerLatex);
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
      unknownKind: GeometryUnknownKind.length,
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

  /// Builds a solved right-triangle **trig-ratio** scene (one known side + one
  /// known acute angle → another side via SOH CAH TOA), or `null` when the data
  /// is inconsistent or contradicts [expectedAnswerLatex]. The missing length
  /// is computed here — never taken from the model.
  static GeometryScene? tryBuildRightTriangleTrig({
    required double knownAngleDeg,
    required String knownAngleLabel,
    required List<GeometryTrigSide> sides,
    required String unknownLabel,
    String? ruleName,
    String? caption,
    String? expectedAnswerLatex,
  }) {
    // The known angle must be genuinely acute (the right angle is implied).
    if (!knownAngleDeg.isFinite || knownAngleDeg <= 0 || knownAngleDeg >= 90) {
      return null;
    }
    // Exactly one known side, one asked side. Figures often label the third
    // side too, so a 3-entry list is accepted when the ASKED unknown is
    // identifiable by the problem's own unknown label — the leftover
    // valueless side is simply not drawn. All roles must stay distinct.
    if (sides.length < 2 || sides.length > 3) return null;
    if (sides.map((s) => s.role).toSet().length != sides.length) return null;
    final knowns = sides.where((s) => s.value != null).toList();
    final unknowns = sides.where((s) => s.value == null).toList();
    if (knowns.length != 1 || unknowns.isEmpty) return null;
    final known = knowns.first;
    final GeometryTrigSide unknown;
    if (unknowns.length == 1) {
      unknown = unknowns.first;
    } else {
      // Two valueless sides: only the one matching the asked label is the
      // unknown; no match means we can't tell which is asked — refuse.
      final asked = unknowns
          .where((s) =>
              s.label.trim().isNotEmpty && s.label.trim() == unknownLabel.trim())
          .toList();
      if (asked.length != 1) return null;
      unknown = asked.first;
    }
    if (known.role == unknown.role) return null;
    if (!known.value!.isFinite || known.value! <= 0) return null;

    final angleLabel =
        knownAngleLabel.trim().isEmpty ? 'θ' : knownAngleLabel.trim();
    // The label comes from the unknown SIDE so the figure, equations and answer
    // all agree; the param is only a fallback.
    final label = unknown.label.trim().isNotEmpty
        ? unknown.label.trim()
        : (unknownLabel.trim().isEmpty ? 'x' : unknownLabel.trim());
    // Label collisions would draw one name with two different values (and
    // bleed step highlights across elements) — refuse the self-contradiction.
    final knownSideName =
        known.label.trim().isEmpty ? '' : known.label.trim();
    if (label == angleLabel || label == knownSideName) return null;
    if (knownSideName.isNotEmpty && knownSideName == angleLabel) return null;

    // Derive ALL THREE side lengths from the known side + angle, then read the
    // unknown off its role — the whole triangle is determined.
    final t = _rad(knownAngleDeg);
    final double opp, adj, hyp;
    switch (known.role) {
      case GeometryTrigSideRole.hypotenuse:
        hyp = known.value!;
        opp = hyp * math.sin(t);
        adj = hyp * math.cos(t);
      case GeometryTrigSideRole.opposite:
        opp = known.value!;
        hyp = opp / math.sin(t);
        adj = opp / math.tan(t);
      case GeometryTrigSideRole.adjacent:
        adj = known.value!;
        hyp = adj / math.cos(t);
        opp = adj * math.tan(t);
    }
    if (![opp, adj, hyp].every((v) => v.isFinite && v > 0)) return null;
    final unknownValue = switch (unknown.role) {
      GeometryTrigSideRole.opposite => opp,
      GeometryTrigSideRole.adjacent => adj,
      GeometryTrigSideRole.hypotenuse => hyp,
    };

    // Cross-check against the solver's verified answer, when we have one.
    // Lengths have arbitrary magnitude, so the tolerance is RELATIVE (a flat
    // 0.5 would wave through a role-swapped figure at unit-sized values).
    final expected = _parseExpectedValue(expectedAnswerLatex);
    final lenTol = math.max(0.01, 0.01 * unknownValue.abs());
    if (expected != null && (expected - unknownValue).abs() > lenTol) {
      return null;
    }

    // Which ratio links the known and unknown roles: SOH / CAH / TOA. The
    // numerator/denominator order is fixed by the ratio itself.
    final roles = {known.role, unknown.role};
    final String fnLatex, fnName;
    final GeometryTrigSideRole numRole;
    if (roles.containsAll(const {
      GeometryTrigSideRole.opposite,
      GeometryTrigSideRole.hypotenuse,
    })) {
      fnLatex = '\\sin';
      fnName = 'sin';
      numRole = GeometryTrigSideRole.opposite;
    } else if (roles.containsAll(const {
      GeometryTrigSideRole.adjacent,
      GeometryTrigSideRole.hypotenuse,
    })) {
      fnLatex = '\\cos';
      fnName = 'cos';
      numRole = GeometryTrigSideRole.adjacent;
    } else {
      fnLatex = '\\tan';
      fnName = 'tan';
      numRole = GeometryTrigSideRole.opposite;
    }
    String roleName(GeometryTrigSideRole r) => switch (r) {
          GeometryTrigSideRole.opposite => 'opposite',
          GeometryTrigSideRole.adjacent => 'adjacent',
          GeometryTrigSideRole.hypotenuse => 'hypotenuse',
        };
    final unknownIsNum = unknown.role == numRole;
    final knownDisplay = formatLength(known.value!);
    final numDisplay = unknownIsNum ? label : knownDisplay;
    final denDisplay = unknownIsNum ? knownDisplay : label;
    final denRole = numRole == GeometryTrigSideRole.opposite &&
            roles.contains(GeometryTrigSideRole.adjacent)
        ? GeometryTrigSideRole.adjacent
        : GeometryTrigSideRole.hypotenuse;
    final ruleEq =
        '$fnLatex(${_deg(knownAngleDeg)}) = \\frac{$numDisplay}{$denDisplay}';
    final rearrange = unknownIsNum
        ? '$label = $knownDisplay \\times $fnLatex(${_deg(knownAngleDeg)})'
        : '$label = \\frac{$knownDisplay}{$fnLatex(${_deg(knownAngleDeg)})}';

    // Right angle at C = (0,0); adjacent leg along +x to A (where the known
    // angle sits), opposite leg along +y to B — the drawn angle at A is
    // exactly the given angle, correct by construction.
    final vertices = <VisualPoint>[
      const VisualPoint(0, 0), // C (right angle) — index 0
      VisualPoint(adj, 0), // A (the known angle) — index 1
      VisualPoint(0, opp), // B — index 2
    ];
    // Edge 0: C→A (adjacent); edge 1: A→B (hypotenuse); edge 2: B→C (opposite).
    int edgeFor(GeometryTrigSideRole r) => switch (r) {
          GeometryTrigSideRole.adjacent => 0,
          GeometryTrigSideRole.hypotenuse => 1,
          GeometryTrigSideRole.opposite => 2,
        };
    final builtSides = [
      GeometrySide(
        label: known.label.trim().isEmpty ? roleName(known.role) : known.label.trim(),
        edge: edgeFor(known.role),
        value: known.value!,
      ),
      GeometrySide(
        label: label,
        edge: edgeFor(unknown.role),
        value: unknownValue,
        isUnknown: true,
      ),
    ];
    final builtAngle = GeometryAngle(
      label: angleLabel,
      vertex: 1,
      ray1: 0,
      ray2: 2,
      value: knownAngleDeg,
    );

    final resolvedRule = (ruleName != null && ruleName.trim().isNotEmpty)
        ? ruleName.trim()
        : 'Trigonometric ratios: SOH CAH TOA';
    final resolvedCaption = (caption != null && caption.trim().isNotEmpty)
        ? caption.trim()
        : resolvedRule;

    final knownSideLabel = builtSides.first.label;
    final knownText =
        '$knownSideLabel = $knownDisplay and $angleLabel = ${_degPlain(knownAngleDeg)}';
    final steps = <GeometryStep>[
      GeometryStep(
        focus: GeometryStepFocus.known,
        title: 'Start with what we know',
        detail: 'One side and one angle are given: $knownText.',
        highlight: {knownSideLabel, angleLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.rule,
        title: 'Pick the trig ratio',
        detail:
            'The ${roleName(known.role)} and ${roleName(unknown.role)} sides '
            'are linked by $fnName: $fnName of the angle = '
            '${roleName(numRole)} ÷ ${roleName(denRole)} (SOH CAH TOA).',
        equationLatex: ruleEq,
        highlight: {knownSideLabel, label, angleLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.unknown,
        title: 'Find the missing side',
        detail: 'Rearrange to leave $label on its own.',
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
      kind: GeometrySceneKind.rightTriangleTrig,
      figureKind: GeometryFigureKind.polygon,
      vertices: vertices,
      angles: [builtAngle],
      sides: builtSides,
      unknownKind: GeometryUnknownKind.length,
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

  /// Builds a solved **sine-rule angle** scene (two sides + a non-included
  /// angle → the angle opposite the other given side), or `null` when the data
  /// is inconsistent, genuinely ambiguous with no disambiguating signal, or
  /// contradicts [expectedAnswerLatex]. The angle is computed here — never
  /// taken from the model; [branch] only picks between the two app-computed
  /// SSA candidates when the problem itself states acute/obtuse.
  static GeometryScene? tryBuildSineRuleAngle({
    required double knownAngleDeg,
    required String knownAngleLabel,
    required double sideOppositeKnown,
    required String sideOppositeKnownLabel,
    required double sideOppositeUnknown,
    required String sideOppositeUnknownLabel,
    required String unknownLabel,
    AngleBranchHint? branch,
    String? ruleName,
    String? caption,
    String? expectedAnswerLatex,
  }) {
    if (!knownAngleDeg.isFinite || knownAngleDeg <= 0 || knownAngleDeg >= 180) {
      return null;
    }
    if (!sideOppositeKnown.isFinite || sideOppositeKnown <= 0) return null;
    if (!sideOppositeUnknown.isFinite || sideOppositeUnknown <= 0) return null;

    final label = unknownLabel.trim().isEmpty ? 'x' : unknownLabel.trim();
    final angleLabel =
        knownAngleLabel.trim().isEmpty ? 'A' : knownAngleLabel.trim();
    final skLabel = sideOppositeKnownLabel.trim().isEmpty
        ? 'a'
        : sideOppositeKnownLabel.trim();
    final suLabel = sideOppositeUnknownLabel.trim().isEmpty
        ? 'b'
        : sideOppositeUnknownLabel.trim();
    // Label collisions would draw one name with two different values (and
    // bleed step highlights across elements) — refuse the self-contradiction.
    if ({label, angleLabel, skLabel, suLabel}.length != 4) return null;

    // sin(unknown) = (side opposite the unknown) · sin(known) / (side opposite
    // the known). A ratio above 1 means no such triangle exists.
    final ratio =
        sideOppositeUnknown * math.sin(_rad(knownAngleDeg)) / sideOppositeKnown;
    if (!ratio.isFinite || ratio <= 0 || ratio > 1 + 1e-9) return null;
    final acuteDeg = _degrees(math.asin(math.min(1, ratio)));
    final obtuseDeg = 180 - acuteDeg;
    bool valid(double theta) =>
        theta > 1e-9 && theta + knownAngleDeg < 180 - 1e-9;

    // Select the branch — by the problem's own wording first, then the
    // verified answer, then uniqueness. NEVER by guessing: a genuinely
    // ambiguous SSA with no signal returns null (honest fallback).
    final expected = _parseExpectedValue(expectedAnswerLatex);
    double? theta;
    var isObtuseBranch = false;
    if (branch != null) {
      final candidate =
          branch == AngleBranchHint.obtuse ? obtuseDeg : acuteDeg;
      if (!valid(candidate)) return null;
      theta = candidate;
      isObtuseBranch = branch == AngleBranchHint.obtuse;
    } else {
      final candidates = <(double, bool)>[
        if (valid(acuteDeg)) (acuteDeg, false),
        if (valid(obtuseDeg) && (obtuseDeg - acuteDeg).abs() > 0.5)
          (obtuseDeg, true),
      ];
      if (candidates.isEmpty) return null;
      if (expected != null) {
        final matching = candidates
            .where((c) => (c.$1 - expected).abs() <= 0.5)
            .toList();
        if (matching.length != 1) return null;
        theta = matching.first.$1;
        isObtuseBranch = matching.first.$2;
      } else if (candidates.length == 1) {
        theta = candidates.first.$1;
        isObtuseBranch = candidates.first.$2;
      } else {
        return null; // ambiguous, no signal — refuse to guess
      }
    }

    // Cross-check the chosen branch against the verified answer too.
    if (expected != null && (expected - theta).abs() > 0.5) return null;
    final thirdDeg = 180 - knownAngleDeg - theta;
    if (thirdDeg <= 0) return null;

    // Place the triangle from its REAL side lengths: the unknown angle at the
    // origin, the third side along +x, so every drawn side/angle is true.
    //   U (unknown angle) at (0,0); K (known angle) at (c, 0);
    //   T at sideOppositeKnown away from U, at the unknown angle θ.
    final c = sideOppositeKnown *
        math.sin(_rad(thirdDeg)) /
        math.sin(_rad(knownAngleDeg));
    if (!c.isFinite || c <= 0) return null;
    final vertices = <VisualPoint>[
      const VisualPoint(0, 0), // U — index 0
      VisualPoint(c, 0), // K — index 1
      VisualPoint(
        sideOppositeKnown * math.cos(_rad(theta)),
        sideOppositeKnown * math.sin(_rad(theta)),
      ), // T — index 2
    ];
    // Defensive consistency: the drawn K→T edge must equal the given side
    // opposite the unknown (the construction and the sine rule must agree).
    final ktLen = math.sqrt(
      math.pow(vertices[2].x - vertices[1].x, 2) +
          math.pow(vertices[2].y - vertices[1].y, 2),
    );
    if ((ktLen - sideOppositeUnknown).abs() >
        1e-6 * math.max(1, sideOppositeUnknown)) {
      return null;
    }

    final builtAngles = [
      GeometryAngle(
        label: label,
        vertex: 0,
        ray1: 1,
        ray2: 2,
        value: theta,
        isUnknown: true,
      ),
      GeometryAngle(
        label: angleLabel,
        vertex: 1,
        ray1: 0,
        ray2: 2,
        value: knownAngleDeg,
      ),
    ];
    // Consistency gate (same spirit as tryBuild): the drawn unknown wedge must
    // carry exactly the computed measure.
    final drawnTheta = _angleBetween(vertices[0], vertices[1], vertices[2]);
    if ((drawnTheta - theta).abs() > 0.5) return null;

    // Edge 0: U→K (third side, unlabeled); edge 1: K→T (side opposite the
    // unknown); edge 2: T→U (side opposite the known angle).
    final builtSides = [
      GeometrySide(label: suLabel, edge: 1, value: sideOppositeUnknown),
      GeometrySide(label: skLabel, edge: 2, value: sideOppositeKnown),
    ];

    final resolvedRule = (ruleName != null && ruleName.trim().isNotEmpty)
        ? ruleName.trim()
        : 'The sine rule: a / sin A = b / sin B';
    final resolvedCaption = (caption != null && caption.trim().isNotEmpty)
        ? caption.trim()
        : resolvedRule;

    final skDisplay = formatLength(sideOppositeKnown);
    final suDisplay = formatLength(sideOppositeUnknown);
    final knownText = '$suLabel = $suDisplay, $skLabel = $skDisplay and '
        '$angleLabel = ${_degPlain(knownAngleDeg)}';
    final inverse =
        '\\sin^{-1}(\\frac{$suDisplay \\times \\sin ${_deg(knownAngleDeg)}}{$skDisplay})';
    final steps = <GeometryStep>[
      GeometryStep(
        focus: GeometryStepFocus.known,
        title: 'Start with what we know',
        detail: 'Two sides and an angle are given: $knownText.',
        highlight: {suLabel, skLabel, angleLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.rule,
        title: 'The sine rule',
        detail: 'In any triangle, each side divided by the sine of its '
            'opposite angle gives the same value.',
        equationLatex:
            '\\frac{\\sin $label}{$suDisplay} = \\frac{\\sin ${_deg(knownAngleDeg)}}{$skDisplay}',
        highlight: {suLabel, skLabel, angleLabel, label},
      ),
      GeometryStep(
        focus: GeometryStepFocus.unknown,
        title: 'Find the missing angle',
        detail: isObtuseBranch
            ? 'Take the inverse sine, then subtract from 180° — the problem '
                'says $label is obtuse, and sin is the same for an angle and '
                'its supplement.'
            : 'Rearrange and take the inverse sine.',
        equationLatex: isObtuseBranch
            ? '$label = 180^\\circ - $inverse'
            : '$label = $inverse',
        highlight: {label},
      ),
      GeometryStep(
        focus: GeometryStepFocus.answer,
        title: 'Answer',
        detail: 'The missing angle is ${_degPlain(theta)}.',
        equationLatex: '$label = ${_deg(theta)}',
        highlight: {label},
      ),
    ];

    final semantics = 'Triangle diagram. Given $knownText. $resolvedRule. '
        'The missing angle $label is ${_degPlain(theta)}.';

    return GeometryScene(
      kind: GeometrySceneKind.sineRuleAngle,
      figureKind: GeometryFigureKind.polygon,
      vertices: vertices,
      angles: builtAngles,
      sides: builtSides,
      unknownLabel: label,
      unknownValue: theta,
      ruleName: resolvedRule,
      caption: resolvedCaption,
      semanticsLabel: semantics,
      steps: steps,
      polygonRing: const [0, 1, 2],
    );
  }

  /// Builds a solved **SAS area** scene (two sides + the included angle →
  /// Area = ½·a·b·sin C), or `null` when the data is inconsistent or
  /// contradicts [expectedAnswerLatex]. The area is computed here — never
  /// taken from the model.
  static GeometryScene? tryBuildSasArea({
    required double sideA,
    required String sideALabel,
    required double sideB,
    required String sideBLabel,
    required double includedAngleDeg,
    required String angleLabel,
    String unknownLabel = 'Area',
    String? ruleName,
    String? caption,
    String? expectedAnswerLatex,
  }) {
    if (!sideA.isFinite || sideA <= 0) return null;
    if (!sideB.isFinite || sideB <= 0) return null;
    if (!includedAngleDeg.isFinite ||
        includedAngleDeg <= 0 ||
        includedAngleDeg >= 180) {
      return null;
    }

    final label = unknownLabel.trim().isEmpty ? 'Area' : unknownLabel.trim();
    final aLabel = sideALabel.trim().isEmpty ? 'a' : sideALabel.trim();
    final bLabel = sideBLabel.trim().isEmpty ? 'b' : sideBLabel.trim();
    final cLabel = angleLabel.trim().isEmpty ? 'C' : angleLabel.trim();
    // Label collisions would draw one name with two different values (and
    // bleed step highlights across elements) — refuse the self-contradiction.
    if ({label, aLabel, bLabel, cLabel}.length != 4) return null;

    final area = 0.5 * sideA * sideB * math.sin(_rad(includedAngleDeg));
    if (!area.isFinite || area <= 0) return null;

    // Cross-check against the solver's verified answer, when we have one.
    // Areas have arbitrary magnitude, so the tolerance is RELATIVE (a flat
    // 0.5 would wave through a wrong figure at unit-sized values).
    final expected = _parseExpectedValue(expectedAnswerLatex);
    final areaTol = math.max(0.01, 0.01 * area.abs());
    if (expected != null && (expected - area).abs() > areaTol) return null;

    // The included angle's vertex at the origin, side a along +x, side b at
    // the given angle — the drawn wedge is the real angle between the real
    // sides, correct by construction.
    final vertices = <VisualPoint>[
      const VisualPoint(0, 0), // A (the included angle) — index 0
      VisualPoint(sideA, 0), // B — index 1
      VisualPoint(
        sideB * math.cos(_rad(includedAngleDeg)),
        sideB * math.sin(_rad(includedAngleDeg)),
      ), // C — index 2
    ];
    // Edge 0: A→B (side a); edge 1: B→C (third side, unlabeled); edge 2: C→A
    // (side b).
    final builtSides = [
      GeometrySide(label: aLabel, edge: 0, value: sideA),
      GeometrySide(label: bLabel, edge: 2, value: sideB),
    ];
    final builtAngle = GeometryAngle(
      label: cLabel,
      vertex: 0,
      ray1: 1,
      ray2: 2,
      value: includedAngleDeg,
    );

    final resolvedRule = (ruleName != null && ruleName.trim().isNotEmpty)
        ? ruleName.trim()
        : 'Area of a triangle: ½ · a · b · sin C';
    final resolvedCaption = (caption != null && caption.trim().isNotEmpty)
        ? caption.trim()
        : resolvedRule;

    final aDisplay = formatLength(sideA);
    final bDisplay = formatLength(sideB);
    final knownText = '$aLabel = $aDisplay, $bLabel = $bDisplay and '
        '$cLabel = ${_degPlain(includedAngleDeg)}';
    final labelLatex = label.length > 1 ? '\\text{$label}' : label;
    final steps = <GeometryStep>[
      GeometryStep(
        focus: GeometryStepFocus.known,
        title: 'Start with what we know',
        detail:
            'Two sides and the angle between them are given: $knownText.',
        highlight: {aLabel, bLabel, cLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.rule,
        title: 'The area rule',
        detail: 'Area = half × one side × the other side × sin of the angle '
            'between them.',
        equationLatex:
            '$labelLatex = \\frac{1}{2} \\times $aLabel \\times $bLabel \\times \\sin $cLabel',
        highlight: {aLabel, bLabel, cLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.unknown,
        title: 'Work out the area',
        detail: 'Substitute the numbers.',
        equationLatex:
            '$labelLatex = \\frac{1}{2} \\times $aDisplay \\times $bDisplay \\times \\sin(${_deg(includedAngleDeg)})',
        highlight: {aLabel, bLabel, cLabel},
      ),
      GeometryStep(
        focus: GeometryStepFocus.answer,
        title: 'Answer',
        detail: 'The area is ${formatLength(area)}.',
        equationLatex: '$labelLatex = ${formatLength(area)}',
        highlight: {label},
      ),
    ];

    final semantics = 'Triangle diagram. Given $knownText. $resolvedRule. '
        'The area is ${formatLength(area)}.';

    return GeometryScene(
      kind: GeometrySceneKind.sasArea,
      figureKind: GeometryFigureKind.polygon,
      vertices: vertices,
      angles: [builtAngle],
      sides: builtSides,
      unknownKind: GeometryUnknownKind.area,
      unknownLabel: label,
      unknownValue: area,
      ruleName: resolvedRule,
      caption: resolvedCaption,
      semanticsLabel: semantics,
      steps: steps,
      polygonRing: const [0, 1, 2],
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
        GeometrySceneKind.rightTrianglePythagoras ||
        GeometrySceneKind.rightTriangleTrig ||
        GeometrySceneKind.sineRuleAngle ||
        GeometrySceneKind.sasArea =>
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
        GeometrySceneKind.rightTrianglePythagoras ||
        GeometrySceneKind.rightTriangleTrig ||
        GeometrySceneKind.sineRuleAngle ||
        GeometrySceneKind.sasArea =>
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
        GeometrySceneKind.rightTrianglePythagoras ||
        GeometrySceneKind.rightTriangleTrig ||
        GeometrySceneKind.sineRuleAngle ||
        GeometrySceneKind.sasArea =>
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
        GeometrySceneKind.rightTrianglePythagoras ||
        GeometrySceneKind.rightTriangleTrig ||
        GeometrySceneKind.sineRuleAngle ||
        GeometrySceneKind.sasArea =>
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
      case GeometrySceneKind.rightTriangleTrig:
      case GeometrySceneKind.sineRuleAngle:
      case GeometrySceneKind.sasArea:
        // These are side/mixed-given kinds built via their OWN builders
        // (tryBuildPythagoras / tryBuildRightTriangleTrig / tryBuildSineRuleAngle
        // / tryBuildSasArea), never through the angle path — unreachable here.
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

  static double _degrees(double rad) => rad * 180 / math.pi;

  /// The interior angle (degrees) at [v] between the rays toward [p] and [q].
  static double _angleBetween(VisualPoint v, VisualPoint p, VisualPoint q) {
    final a1 = math.atan2(p.y - v.y, p.x - v.x);
    final a2 = math.atan2(q.y - v.y, q.x - v.x);
    var d = (a2 - a1).abs();
    if (d > math.pi) d = 2 * math.pi - d;
    return _degrees(d);
  }

  /// Delimiter-free LaTeX for a degree value, e.g. `80^\circ`.
  static String _deg(double value) => '${formatDegrees(value)}^\\circ';

  /// Plain-text degree value for prose/semantics, e.g. `80°`.
  static String _degPlain(double value) => '${formatDegrees(value)}°';

  /// Extracts the VALUE of a verified-answer LaTeX string (`x = 80^\circ`,
  /// `\frac{1}{2}`, `45`), or `null` when no single number can be read
  /// reliably — a naive first-number grab would read `\frac{1}{2}` as 1 and
  /// make the cross-check gate accept a wrong scene or reject a right one.
  /// Unparseable (symbolic √/π forms, mixed expressions) skips the gate
  /// rather than misparsing: a wrong gate is worse than no gate.
  static double? _parseExpectedValue(String? source) {
    if (source == null) return null;
    var s = source.trim();
    if (s.isEmpty) return null;
    // Answers read "x = 80^\circ" (or chains ending in the value): take the
    // RHS of the LAST '='.
    final eq = s.lastIndexOf('=');
    if (eq >= 0) s = s.substring(eq + 1);
    s = s
        .replaceAll(RegExp(r'\^\{?\\circ\}?'), '')
        .replaceAll('°', '')
        .replaceAll(RegExp(r'\\text\{[^}]*\}'), '')
        .trim();
    final frac = RegExp(r'^\\[dt]?frac\{(-?\d+(?:\.\d+)?)\}\{(-?\d+(?:\.\d+)?)\}$')
        .firstMatch(s);
    if (frac != null) {
      final num = double.tryParse(frac.group(1)!);
      final den = double.tryParse(frac.group(2)!);
      if (num == null || den == null || den == 0) return null;
      return num / den;
    }
    if (RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(s)) return double.tryParse(s);
    return null;
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
