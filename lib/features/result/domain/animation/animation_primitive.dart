/// UNIVERSAL ANIMATED LEARNING ENGINE — the animation-primitive taxonomy.
///
/// Every step of an [AnimationScript] declares ONE [AnimationPrimitive]: the
/// kind of transformation the renderer should stage. The list is deliberately
/// broad (the brief's ~35 named animations) but the renderer never crashes on an
/// unknown value — [AnimationPrimitive.parse] is TOTAL and degrades to
/// [AnimationPrimitive.equationMorph], the universal fallback that animates any
/// before→after LaTeX pair. So a newer server (or a future primitive) can never
/// break an older client, exactly like the teaching-layer enums.
library;

/// The kind of animated transformation a step stages. Grouped by the brief's
/// families; the renderer dispatches on this.
enum AnimationPrimitive {
  // ---- Equation transforms (rendered by EquationMorphView) ----
  /// Generic before→after token morph — the universal fallback.
  equationMorph,

  /// Glow a term/subexpression in place (no structural change).
  highlightTerm,

  /// A term visibly slides across the `=` and flips sign (the balance idea).
  moveTermAcrossEquals,

  /// Two terms combine into one (e.g. `20 - 5 → 15`).
  mergeTerms,

  /// One expression splits into factors/parts (e.g. `x^2+5x+6 → (x+2)(x+3)`).
  splitExpression,

  /// Factor a quadratic/expression.
  factorExpression,

  /// Expand brackets.
  expandExpression,

  /// A pair of equal-and-opposite terms cancels to nothing.
  cancelTerms,

  /// Substitute a known value into a variable.
  substituteValue,

  /// A fraction transforms (equivalent form / simplification).
  transformFraction,

  // ---- Visual-object primitives (rendered by a CustomPainter panel) ----
  /// A two-pan balance (linear equations — why both sides stay equal).
  balanceScale,

  /// An area/grid model (multiplication, factoring, completing the square).
  areaModel,

  /// Partitioned fraction bars.
  fractionBar,

  /// A pie chart (percentages / proportions).
  pieChart,

  /// A bar chart (statistics / data).
  barChart,

  /// A number line highlighting a value/interval.
  numberLine,

  /// The unit circle with a marked angle (trigonometry).
  unitCircle,

  /// A probability tree diagram.
  treeDiagram,

  /// A spinner / sample-space wheel (probability).
  probabilitySpinner,

  // ---- Graphs & calculus ----
  /// Plot a function's curve.
  plotFunction,

  /// Mark a point / intercept on a graph.
  graphPoint,

  /// Animate a slope / gradient.
  slopeAnimation,

  /// Sweep a tangent line along a curve (derivative).
  derivativeAnimation,

  /// Fill the area under a curve with Riemann rectangles → the integral.
  integralArea,

  // ---- Linear algebra ----
  /// A matrix row/column operation.
  matrixTransform,

  /// Vector arrows (magnitude / direction / addition).
  vectorMovement,

  // ---- Beats ----
  /// The celebratory final-answer beat.
  success;

  /// TOTAL, non-throwing parse. Unknown/blank → [equationMorph].
  static AnimationPrimitive parse(String? raw) {
    if (raw == null) return AnimationPrimitive.equationMorph;
    final key = raw.trim();
    for (final v in AnimationPrimitive.values) {
      if (v.name == key) return v;
    }
    return AnimationPrimitive.equationMorph;
  }

  /// Whether this primitive is staged by the symbol-level [EquationMorphView]
  /// (vs a dedicated visual-object painter panel).
  bool get isEquationMorph => switch (this) {
        AnimationPrimitive.equationMorph ||
        AnimationPrimitive.highlightTerm ||
        AnimationPrimitive.moveTermAcrossEquals ||
        AnimationPrimitive.mergeTerms ||
        AnimationPrimitive.splitExpression ||
        AnimationPrimitive.factorExpression ||
        AnimationPrimitive.expandExpression ||
        AnimationPrimitive.cancelTerms ||
        AnimationPrimitive.substituteValue ||
        AnimationPrimitive.transformFraction =>
          true,
        _ => false,
      };
}
