import 'package:flutter/foundation.dart';

/// The kinds of figure a practice question can carry. Kept independent of the
/// result/visual layer's `VisualConceptKind` so the practice domain stays
/// decoupled — the render widget maps between them.
enum PracticeFigureKind {
  /// A closed polygon (triangle, quadrilateral, …) from [PracticeFigure.vertices],
  /// with optional right-angle marks and equal-side tick marks.
  polygon,

  /// A plain circle with a labelled radius or diameter ([PracticeFigure.circleLabel]).
  circle,

  /// Two angles on a straight line — [PracticeFigure.vertices] are `[A, O, B, C]`
  /// (A,O,B collinear; C the ray tip); the given A-O-C angle is labelled.
  straightLineAngles,
}

/// A point in the figure's OWN coordinate space. The renderer auto-scales and
/// centres the figure, so templates can use natural units (e.g. side lengths).
@immutable
class PracticeFigurePoint {
  const PracticeFigurePoint(this.x, this.y);

  final double x;
  final double y;
}

/// A small, deterministic geometry figure attached to a practice question.
///
/// **Golden rule (figures = answers):** a `PracticeFigure` is built by a rule
/// template from its OWN verified numbers — never LLM-invented. A triangle
/// labelled 86°/37° must actually BE 86°/37°, because the same template that
/// picks the numbers builds the figure. Drawn on-device via `ConceptPainter`
/// (Stage 2); no assets, no network.
///
/// The label lists are OPTIONAL and align positionally: [vertexLabels] and
/// [angleLabels] to [vertices] (index i), [sideLabels] to the edge i→i+1. Use
/// an empty string to skip a single label within a list. Stage 4 populates all
/// of this; Stage 3 only defines the type and its rendering.
@immutable
class PracticeFigure {
  const PracticeFigure({
    required this.kind,
    required this.semanticsLabel,
    this.vertices = const [],
    this.vertexLabels = const [],
    this.angleLabels = const [],
    this.sideLabels = const [],
    this.rightAngleVertices = const [],
    this.tickEdges = const {},
    this.circleLabel,
    this.circleShowDiameter = false,
    this.lineGivenLabel,
  });

  final PracticeFigureKind kind;

  /// Plain-text description read to screen-reader users — a figure is otherwise
  /// invisible to them, so this is REQUIRED (a11y).
  final String semanticsLabel;

  /// Points in order — polygon vertices, or `[A, O, B, C]` for a straight-line.
  final List<PracticeFigurePoint> vertices;

  /// Optional vertex names, aligned to [vertices] (e.g. `['A','B','C']`).
  final List<String> vertexLabels;

  /// Optional angle values, aligned to [vertices] (e.g. `['86°','37°','']` —
  /// leave the UNKNOWN/answer angle blank so the figure never spoils it).
  final List<String> angleLabels;

  /// Optional side lengths, aligned to the edge from vertex i to i+1
  /// (e.g. `['5','','']` — leave the answer side blank).
  final List<String> sideLabels;

  /// Vertex indices that carry a right-angle mark (e.g. Pythagoras / base×height).
  final List<int> rightAngleVertices;

  /// Edge index → congruence-tick count, marking equal sides (e.g. isosceles).
  final Map<int, int> tickEdges;

  /// For [PracticeFigureKind.circle]: the text on the radius/diameter line
  /// (the given measure).
  final String? circleLabel;

  /// For [PracticeFigureKind.circle]: draw a diameter instead of a radius.
  final bool circleShowDiameter;

  /// For [PracticeFigureKind.straightLineAngles]: the given (A-O-C) angle text.
  final String? lineGivenLabel;
}
