/// How a practice question is produced — the Stage 15 hybrid generation
/// strategy. Choosing the cheapest capable tier per skill is what keeps the
/// engine unlimited *and* cost-efficient.
enum GenerationTier {
  /// Tier 1 — pure template + randomized parameters, generated instantly and
  /// entirely on-device (no network). Arithmetic, fractions, ratios,
  /// percentages, basic & intermediate algebra.
  template('Template'),

  /// Tier 2 — rule/constraint-based generation, still on-device but built from
  /// mathematical constraints rather than a fixed template. Geometry,
  /// measurement, trigonometry, statistics, probability.
  ruleBased('Rule-based'),

  /// Tier 3 — AI-generated via the `generatePracticeQuestion` Cloud Function.
  /// Used only where templates/rules can't reach: calculus, vectors, matrices,
  /// proofs and university mathematics. Pro-only, batched and cached to
  /// minimize OpenAI usage.
  ai('AI');

  const GenerationTier(this.label);

  final String label;

  /// Whether producing this tier needs the network / backend.
  bool get requiresBackend => this == GenerationTier.ai;
}
