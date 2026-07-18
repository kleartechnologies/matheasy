/// The strict, deterministic generation rules for one [PracticeDifficulty].
///
/// Difficulty is not just a label — it is a contract that directly controls
/// question generation. Every generator reads its target difficulty's [spec] to
/// bound number ranges, operation counts and concept depth; the
/// `DifficultyValidator` uses the same spec to accept or reject a candidate. A
/// question is only ever produced (or kept) if it fits the spec of the level the
/// user selected — never silently upgraded or downgraded.
///
/// The specs are grouped by the target learner:
///  * Very Easy  — primary school
///  * Easy       — upper primary / early secondary
///  * Medium     — secondary / SPM / GCSE
///  * Hard       — advanced secondary / A-Level
///  * Expert     — university
class DifficultySpec {
  const DifficultySpec({
    required this.gradeLabel,
    required this.targetSteps,
    required this.maxSteps,
    required this.maxOperations,
    required this.numberMax,
    required this.allowNegatives,
    required this.allowFractions,
    required this.allowAlgebra,
    required this.estimatedSolveTimeSeconds,
  });

  /// Human grade band shown in metadata + analytics (e.g. "A-Level").
  final String gradeLabel;

  /// The ideal number of solving steps a question at this level should take.
  final int targetSteps;

  /// The hard ceiling on solving steps — a candidate over this is rejected.
  final int maxSteps;

  /// The most distinct operations a question at this level may combine.
  final int maxOperations;

  /// The largest integer magnitude generators should draw at this level.
  final int numberMax;

  /// Whether negative numbers may appear (off for primary).
  final bool allowNegatives;

  /// Whether fractions may appear outside an explicit fractions topic.
  final bool allowFractions;

  /// Whether algebra may appear outside an explicit algebra-basics topic.
  final bool allowAlgebra;

  /// A rough solve-time budget, stored per question for XP/analytics balancing.
  final int estimatedSolveTimeSeconds;
}

/// Primary school: 1–2 operations, small positive integers, no negatives, no
/// fractions/algebra unless the topic itself is fractions/algebra-basics.
const kVeryEasySpec = DifficultySpec(
  gradeLabel: 'Primary',
  targetSteps: 1,
  maxSteps: 2,
  maxOperations: 2,
  numberMax: 12,
  allowNegatives: false,
  allowFractions: false,
  allowAlgebra: false,
  estimatedSolveTimeSeconds: 20,
);

/// Upper primary / early secondary: up to 3 operations, small equations, basic
/// fractions, simple geometry, basic percentages.
const kEasySpec = DifficultySpec(
  gradeLabel: 'Upper primary / early secondary',
  targetSteps: 2,
  maxSteps: 3,
  maxOperations: 3,
  numberMax: 20,
  allowNegatives: false,
  allowFractions: true,
  allowAlgebra: true,
  estimatedSolveTimeSeconds: 45,
);

/// Secondary / SPM / GCSE: multi-step — factorisation, simultaneous equations,
/// trigonometry basics, quadratics, word problems.
const kMediumSpec = DifficultySpec(
  gradeLabel: 'Secondary / SPM / GCSE',
  targetSteps: 3,
  maxSteps: 5,
  maxOperations: 4,
  numberMax: 50,
  allowNegatives: true,
  allowFractions: true,
  allowAlgebra: true,
  estimatedSolveTimeSeconds: 90,
);

/// Advanced secondary / A-Level: complex algebra, functions, logs, exponentials,
/// differentiation, integration, proofs, multi-step geometry.
const kHardSpec = DifficultySpec(
  gradeLabel: 'Advanced secondary / A-Level',
  targetSteps: 5,
  maxSteps: 8,
  maxOperations: 6,
  numberMax: 100,
  allowNegatives: true,
  allowFractions: true,
  allowAlgebra: true,
  estimatedSolveTimeSeconds: 180,
);

/// University: calculus, linear algebra, matrices, complex numbers, differential
/// equations, advanced probability, multivariable calculus, long derivations.
const kExpertSpec = DifficultySpec(
  gradeLabel: 'University',
  targetSteps: 7,
  maxSteps: 12,
  maxOperations: 10,
  numberMax: 1000,
  allowNegatives: true,
  allowFractions: true,
  allowAlgebra: true,
  estimatedSolveTimeSeconds: 300,
);
