import 'package:flutter/foundation.dart';

/// STAGE 14 — Visual Learning Engine domain models.
///
/// The universal, AI-generated learning structure the Visual tab renders. The
/// backend (`generateVisualSolution`) produces this shape for ANY level of
/// mathematics — primary school through university — and Flutter only
/// visualizes it. No symbolic math ever runs on device: the schema carries
/// everything a renderer needs (steps, explanations, and optional
/// visualization metadata for graphs/shapes).

/// The broad mathematical domain of a problem. Drives which visualization
/// tier renders the solution (see [visualization]) and keeps analytics
/// category-coarse. Designed to grow: adding a value here plus a tier mapping
/// is all a future category needs.
enum ProblemCategory {
  arithmetic('Arithmetic'),
  fractions('Fractions'),
  ratios('Ratios'),
  percentages('Percentages'),
  algebra('Algebra'),
  geometry('Geometry'),
  measurement('Measurement'),
  trigonometry('Trigonometry'),
  statistics('Statistics'),
  probability('Probability'),
  functions('Functions'),
  graphs('Graphs'),
  calculus('Calculus'),
  vectors('Vectors'),
  matrices('Matrices'),
  linearAlgebra('Linear Algebra'),
  differentialEquations('Differential Equations'),
  discreteMathematics('Discrete Mathematics'),
  universityMathematics('University Mathematics');

  const ProblemCategory(this.label);

  final String label;

  /// The default renderer tier for this category.
  ///
  /// Tier 1 (animated transformations) suits equation-rewriting domains;
  /// Tier 2 (interactive cards) suits concept-heavy symbolic domains; Tier 3
  /// (concept explorer) suits anything best understood through a drawing.
  VisualizationType get visualization => switch (this) {
        ProblemCategory.arithmetic ||
        ProblemCategory.fractions ||
        ProblemCategory.ratios ||
        ProblemCategory.percentages ||
        ProblemCategory.algebra ||
        ProblemCategory.measurement =>
          VisualizationType.animatedTransformation,
        ProblemCategory.trigonometry ||
        ProblemCategory.statistics ||
        ProblemCategory.probability ||
        ProblemCategory.matrices ||
        ProblemCategory.vectors ||
        ProblemCategory.linearAlgebra ||
        ProblemCategory.discreteMathematics =>
          VisualizationType.interactiveCards,
        ProblemCategory.geometry ||
        ProblemCategory.functions ||
        ProblemCategory.graphs ||
        ProblemCategory.calculus ||
        ProblemCategory.differentialEquations ||
        ProblemCategory.universityMathematics =>
          VisualizationType.conceptExplorer,
      };
}

/// The schooling level a visual explanation is pitched at. Coarser than
/// [Difficulty] on purpose — it steers tone and depth, not scoring.
enum ProblemDifficulty {
  primary('Primary'),
  secondary('Secondary'),
  preUniversity('Pre-University'),
  university('University');

  const ProblemDifficulty(this.label);

  final String label;
}

/// The three renderer tiers of the Visual Learning Engine.
enum VisualizationType {
  /// Tier 1 — Photomath-style animated equation transformations
  /// (before → operation → after).
  animatedTransformation('Animated steps'),

  /// Tier 2 — expandable, tap-to-learn interactive learning cards.
  interactiveCards('Learning cards'),

  /// Tier 3 — graphs, shapes and coordinate systems in an explorable canvas.
  conceptExplorer('Concept explorer');

  const VisualizationType(this.label);

  final String label;
}

/// A gentle nudge revealed on demand inside a step ("tap to learn").
@immutable
class VisualHint {
  const VisualHint({required this.text});

  final String text;
}

/// One visual transformation: the state before, the operation applied, and the
/// state after — the atom every renderer tier is built from.
@immutable
class VisualStep {
  const VisualStep({
    required this.title,
    required this.beforeLatex,
    required this.afterLatex,
    required this.explanation,
    this.operationLabel,
    this.hint,
  });

  /// Short instruction, e.g. "Subtract 5 from both sides".
  final String title;

  /// The expression before this step, as delimiter-free LaTeX.
  final String beforeLatex;

  /// The expression after this step, as delimiter-free LaTeX.
  final String afterLatex;

  /// Why this step works, in student-friendly language.
  final String explanation;

  /// Optional operation chip, e.g. `− 5`.
  final String? operationLabel;

  /// Optional revealable hint for stuck students.
  final VisualHint? hint;

  /// Plain-language description of the transformation for screen readers.
  String get semanticDescription =>
      '$title. $beforeLatex becomes $afterLatex. $explanation';
}

/// The concept-level takeaway shown after the steps ("what did we learn?").
@immutable
class VisualExplanation {
  const VisualExplanation({required this.summary, this.keyIdeas = const []});

  final String summary;
  final List<String> keyIdeas;
}

/// The named strategy the visual walkthrough follows (e.g. "Balance method").
@immutable
class VisualMethod {
  const VisualMethod({required this.name, required this.description});

  final String name;
  final String description;
}

/// A single (x, y) data point of a [VisualConcept].
@immutable
class VisualPoint {
  const VisualPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is VisualPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// The drawable representations the Tier 3 concept explorer knows how to
/// paint. [generic] means "no canvas" — the explorer falls back to cards.
enum VisualConceptKind {
  /// A straight line `y = slope·x + intercept` (params: `slope`, `intercept`).
  linearGraph,

  /// A parabola `y = a·x² + b·x + c` (params: `a`, `b`, `c`).
  parabolaGraph,

  /// Shaded area under `y = a·x² + b·x + c` between `from` and `to`
  /// (params: `a`, `b`, `c`, `from`, `to`).
  areaUnderCurve,

  /// A number line highlighting `value` (params: `value`, `min`, `max`).
  numberLine,

  /// A partitioned bar showing `numerator` of `denominator` shaded
  /// (params: `numerator`, `denominator`).
  fractionBar,

  /// The unit circle with an angle marked (params: `angleDegrees`).
  unitCircle,

  /// Vertical bars from [VisualConcept.points] (x = position, y = value);
  /// bar names come from [VisualConcept.labels] keyed `'0'`, `'1'`, ….
  barChart,

  /// A closed polygon from [VisualConcept.points] (vertices in order).
  geometryShape,

  /// No drawable form — the explorer renders cards only.
  generic,
}

/// Visualization metadata for the Tier 3 concept explorer. Deliberately
/// loose (a kind + numeric params + points + labels) so the AI can describe
/// any drawing without a schema change, and unknown data degrades to
/// [VisualConceptKind.generic] instead of crashing.
@immutable
class VisualConcept {
  const VisualConcept({
    required this.kind,
    required this.caption,
    this.params = const {},
    this.labels = const {},
    this.points = const [],
  });

  final VisualConceptKind kind;

  /// One-line description of what the drawing shows — also the accessible
  /// label announced by screen readers in place of the canvas.
  final String caption;

  /// Named numeric parameters, e.g. `{'slope': 2, 'intercept': 5}`.
  final Map<String, double> params;

  /// Named display strings, e.g. axis titles or bar names.
  final Map<String, String> labels;

  /// Data points, when the drawing is point-driven.
  final List<VisualPoint> points;

  /// Reads a named parameter with a safe default.
  double param(String name, {double fallback = 0}) =>
      params[name] ?? fallback;
}

/// The complete AI-generated visual learning experience for one problem —
/// the universal schema every tier renders from.
@immutable
class VisualSolution {
  const VisualSolution({
    required this.category,
    required this.difficulty,
    required this.visualization,
    required this.answerLatex,
    required this.intro,
    required this.steps,
    this.explanation,
    this.method,
    this.concept,
  });

  final ProblemCategory category;
  final ProblemDifficulty difficulty;

  /// The resolved renderer tier (explicit from the AI when valid, otherwise
  /// derived from [category] — see `VisualResponseMapper`).
  final VisualizationType visualization;

  /// The final answer as delimiter-free LaTeX.
  final String answerLatex;

  /// Matheasy's one-line welcome to the visual walkthrough.
  final String intro;

  final List<VisualStep> steps;

  /// Optional concept takeaway shown after the last step.
  final VisualExplanation? explanation;

  /// Optional named strategy the walkthrough follows.
  final VisualMethod? method;

  /// Optional drawable metadata (Tier 3).
  final VisualConcept? concept;

  bool get hasSteps => steps.isNotEmpty;
}

/// What the Visual Learning Engine needs to generate a [VisualSolution]:
/// the problem plus (when available) the already-solved answer, so the
/// visual walkthrough always agrees with the Solution tab.
@immutable
class VisualRequest {
  const VisualRequest({
    required this.latex,
    this.answerLatex,
    this.typeHint,
  });

  /// The problem, as delimiter-free LaTeX.
  final String latex;

  /// The answer from the solver, when already known.
  final String? answerLatex;

  /// Coarse problem-type hint from the solver (e.g. "linear").
  final String? typeHint;

  @override
  bool operator ==(Object other) =>
      other is VisualRequest &&
      other.latex == latex &&
      other.answerLatex == answerLatex &&
      other.typeHint == typeHint;

  @override
  int get hashCode => Object.hash(latex, answerLatex, typeHint);
}
