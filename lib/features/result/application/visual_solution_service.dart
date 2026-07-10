import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../../scan/domain/detected_equation.dart';
import '../domain/visual_models.dart';
import 'functions_visual_solution_service.dart';

/// Turns a solved problem into a [VisualSolution] — the AI-generated learning
/// structure the Visual tab renders.
///
/// Same seam pattern as [SolverService]: guests and unconfigured checkouts get
/// the deterministic [MockVisualSolutionService]; signed-in users on a
/// configured backend get [FunctionsVisualSolutionService] (OpenAI behind the
/// `generateVisualSolution` Cloud Function, Pro-gated server-side).
abstract interface class VisualSolutionService {
  Future<VisualSolution> generate(VisualRequest request);
}

/// Thrown when a visual solution can't be produced right now (rate limit,
/// empty AI output). Carries a user-safe [message]; the tab falls back to the
/// Explain tab rather than blocking the solution flow.
class VisualGenerationException implements Exception {
  const VisualGenerationException(this.message);

  final String message;

  @override
  String toString() => 'VisualGenerationException: $message';
}

class VisualTimings {
  const VisualTimings._();

  /// Simulated "drawing" time so the mock shows a brief loading state.
  static const Duration generate = Duration(milliseconds: 500);
}

/// Offline, deterministic visual solutions for the sample problems — keeps
/// the Visual tab fully working for guests, tests and unconfigured checkouts.
class MockVisualSolutionService implements VisualSolutionService {
  const MockVisualSolutionService();

  @override
  Future<VisualSolution> generate(VisualRequest request) async {
    await Future<void>.delayed(VisualTimings.generate);
    final hint = request.typeHint;
    if (hint == EquationKind.linear.name) return _linear;
    if (hint == EquationKind.quadratic.name) return _quadratic;
    if (hint == EquationKind.fraction.name) return _fraction;
    if (hint == EquationKind.trigonometry.name) return _trigonometry;
    return _expression;
  }

  // ---- Linear: 2x + 5 = 13 (Tier 1) ----
  static const VisualSolution _linear = VisualSolution(
    category: ProblemCategory.algebra,
    difficulty: ProblemDifficulty.secondary,
    visualization: VisualizationType.animatedTransformation,
    answerLatex: r'x = 4',
    intro: 'Watch the equation transform — every move keeps both sides '
        'perfectly balanced.',
    steps: [
      VisualStep(
        title: 'Subtract 5 from both sides',
        beforeLatex: r'2x + 5 = 13',
        afterLatex: r'2x = 8',
        operationLabel: '− 5',
        explanation: 'The + 5 is blocking x. Taking 5 off BOTH sides cancels '
            'it while the equation stays balanced.',
        hint: VisualHint(
          text: 'Whatever you do to one side, do to the other — think of a '
              'balance scale.',
        ),
      ),
      VisualStep(
        title: 'Divide both sides by 2',
        beforeLatex: r'2x = 8',
        afterLatex: r'x = 4',
        operationLabel: '÷ 2',
        explanation: '2x means 2 × x. Division undoes multiplication, so '
            'dividing both sides by 2 leaves x on its own.',
      ),
    ],
    explanation: VisualExplanation(
      summary: 'Isolating x is a game of undoing: subtract what was added, '
          'divide by what was multiplied.',
      keyIdeas: [
        'Inverse operations undo each other',
        'Keep both sides balanced at all times',
      ],
    ),
    method: VisualMethod(
      name: 'Balance method',
      description: 'Do the same operation to both sides until x stands alone.',
    ),
  );

  // ---- Quadratic: x² − 5x + 6 = 0 (Tier 1) ----
  static const VisualSolution _quadratic = VisualSolution(
    category: ProblemCategory.algebra,
    difficulty: ProblemDifficulty.secondary,
    visualization: VisualizationType.animatedTransformation,
    answerLatex: r'x = 2 \;\text{or}\; x = 3',
    intro: 'Factorising splits one hard problem into two easy ones — watch it '
        'happen.',
    steps: [
      VisualStep(
        title: 'Factorise the quadratic',
        beforeLatex: r'x^2 - 5x + 6 = 0',
        afterLatex: r'(x - 2)(x - 3) = 0',
        operationLabel: 'factorise',
        explanation: 'We need two numbers that multiply to +6 and add to −5: '
            'that is −2 and −3.',
        hint: VisualHint(
          text: 'List the factor pairs of 6, then check which pair sums to 5.',
        ),
      ),
      VisualStep(
        title: 'Set each factor to zero',
        beforeLatex: r'(x - 2)(x - 3) = 0',
        afterLatex: r'x = 2 \;\text{or}\; x = 3',
        explanation: 'If two things multiply to zero, one of them must BE '
            'zero — so each bracket gives a solution.',
      ),
    ],
    explanation: VisualExplanation(
      summary: 'The zero-product rule turns one quadratic into two simple '
          'linear equations.',
      keyIdeas: [
        'Factor pairs: multiply to c, add to b',
        'A product is zero only when a factor is zero',
      ],
    ),
    method: VisualMethod(
      name: 'Factorisation',
      description: 'Rewrite as a product of brackets, then zero each bracket.',
    ),
    concept: VisualConcept(
      kind: VisualConceptKind.parabolaGraph,
      caption: 'The parabola y = x² − 5x + 6 crosses the x-axis at x = 2 and '
          'x = 3 — exactly the two solutions.',
      params: {'a': 1, 'b': -5, 'c': 6},
    ),
  );

  // ---- Fractions: 1/2 + 1/3 (Tier 1) ----
  static const VisualSolution _fraction = VisualSolution(
    category: ProblemCategory.fractions,
    difficulty: ProblemDifficulty.primary,
    visualization: VisualizationType.animatedTransformation,
    answerLatex: r'\frac{5}{6}',
    intro: 'Fractions can only be added when their pieces are the same size — '
        'watch them match up.',
    steps: [
      VisualStep(
        title: 'Find a common denominator',
        beforeLatex: r'\frac{1}{2} + \frac{1}{3}',
        afterLatex: r'\frac{3}{6} + \frac{2}{6}',
        operationLabel: '× 3⁄3, × 2⁄2',
        explanation: 'Halves and thirds are different-sized pieces. Sixths '
            'work for both: 1/2 = 3/6 and 1/3 = 2/6.',
        hint: VisualHint(
          text: 'The smallest number both 2 and 3 divide into is 6.',
        ),
      ),
      VisualStep(
        title: 'Add the numerators',
        beforeLatex: r'\frac{3}{6} + \frac{2}{6}',
        afterLatex: r'\frac{5}{6}',
        operationLabel: '3 + 2',
        explanation: 'Now the pieces match, just count them: 3 sixths plus '
            '2 sixths makes 5 sixths.',
      ),
    ],
    explanation: VisualExplanation(
      summary: 'Same-sized pieces first, then simply count the pieces.',
      keyIdeas: [
        'A common denominator makes pieces the same size',
        'Only numerators are added — the piece size stays',
      ],
    ),
    concept: VisualConcept(
      kind: VisualConceptKind.fractionBar,
      caption: 'A bar split into 6 equal parts with 5 shaded — five sixths.',
      params: {'numerator': 5, 'denominator': 6},
    ),
  );

  // ---- Trigonometry (Tier 2) ----
  static const VisualSolution _trigonometry = VisualSolution(
    category: ProblemCategory.trigonometry,
    difficulty: ProblemDifficulty.secondary,
    visualization: VisualizationType.interactiveCards,
    answerLatex: r'\theta = 30^\circ',
    intro: 'Trig ratios are just triangle side comparisons — unpack each card '
        'to see the idea.',
    steps: [
      VisualStep(
        title: 'Identify the ratio',
        beforeLatex: r'\sin\theta = \frac{1}{2}',
        afterLatex: r'\theta = \sin^{-1}\!\left(\frac{1}{2}\right)',
        explanation: 'Sine links an angle to opposite ÷ hypotenuse. To get '
            'the angle back, apply the inverse sine.',
        hint: VisualHint(
          text: 'SOH-CAH-TOA: Sine = Opposite over Hypotenuse.',
        ),
      ),
      VisualStep(
        title: 'Evaluate the inverse',
        beforeLatex: r'\theta = \sin^{-1}\!\left(\frac{1}{2}\right)',
        afterLatex: r'\theta = 30^\circ',
        explanation: 'sin 30° = 1/2 is one of the exact values worth '
            'memorising — it comes from a half equilateral triangle.',
      ),
    ],
    explanation: VisualExplanation(
      summary: 'Inverse trig functions turn a known ratio back into the angle '
          'that produced it.',
      keyIdeas: [
        'sin θ compares opposite to hypotenuse',
        '30°, 45°, 60° have exact ratios worth knowing',
      ],
    ),
    concept: VisualConcept(
      kind: VisualConceptKind.unitCircle,
      caption: 'The unit circle with a 30° angle marked — its height above '
          'the axis is exactly one half.',
      params: {'angleDegrees': 30},
    ),
  );

  // ---- Arithmetic expression (Tier 1) ----
  static const VisualSolution _expression = VisualSolution(
    category: ProblemCategory.arithmetic,
    difficulty: ProblemDifficulty.primary,
    visualization: VisualizationType.animatedTransformation,
    answerLatex: r'28',
    intro: 'Order of operations decides what happens first — watch the '
        'expression shrink.',
    steps: [
      VisualStep(
        title: 'Multiply first',
        beforeLatex: r'12 + 8 \times 2',
        afterLatex: r'12 + 16',
        operationLabel: '8 × 2',
        explanation: 'Multiplication comes before addition (BODMAS), so '
            '8 × 2 happens first.',
        hint: VisualHint(
          text: 'BODMAS: Brackets, Orders, Division/Multiplication, '
              'Addition/Subtraction.',
        ),
      ),
      VisualStep(
        title: 'Then add',
        beforeLatex: r'12 + 16',
        afterLatex: r'28',
        operationLabel: '+',
        explanation: 'Only addition is left, so finish it off: 12 + 16 = 28.',
      ),
    ],
    explanation: VisualExplanation(
      summary: 'Evaluate in BODMAS order and the expression collapses one '
          'operation at a time.',
      keyIdeas: ['Multiplication before addition'],
    ),
  );
}

/// Provides the active [VisualSolutionService] — real Cloud Function when the
/// AI backend is available, deterministic mock otherwise (guests keep a fully
/// working Visual tab).
final Provider<VisualSolutionService> visualSolutionServiceProvider =
    Provider<VisualSolutionService>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) {
    return const MockVisualSolutionService();
  }
  final functions = ref.watch(firebaseFunctionsProvider);
  return FunctionsVisualSolutionService(
    (name, data) => callFunction(functions, name, data),
  );
});
