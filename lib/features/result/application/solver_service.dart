import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../../scan/domain/detected_equation.dart';
import '../domain/result_models.dart';
import 'functions_solver_service.dart';

/// Turns a [DetectedEquation] into a full [ResultData] (answer + steps +
/// explanations + methods + practice).
///
/// This is the seam a later stage plugs the real AI into: swap
/// [MockSolverService] for an OpenAI/Claude-backed solver by overriding
/// [solverServiceProvider]. The result screen depends only on this interface
/// and [ResultData], so no UI changes.
abstract interface class SolverService {
  Future<ResultData> solve(DetectedEquation equation);
}

class SolverTimings {
  const SolverTimings._();

  /// Simulated "thinking" time so the UI shows a brief solving state.
  static const Duration solve = Duration(milliseconds: 500);
}

/// Offline, deterministic solver with hand-authored solutions for the sample
/// problems used through Stage 5.
class MockSolverService implements SolverService {
  const MockSolverService();

  @override
  Future<ResultData> solve(DetectedEquation equation) async {
    await Future<void>.delayed(SolverTimings.solve);
    return switch (equation.kind) {
      EquationKind.linear => _linear(equation),
      EquationKind.quadratic => _quadratic(equation),
      EquationKind.fraction => _fraction(equation),
      EquationKind.expression || EquationKind.trigonometry =>
        _fallback(equation),
    };
  }

  // ---- Linear: 2x + 5 = 13 ----
  ResultData _linear(DetectedEquation equation) => ResultData(
        equation: equation,
        type: ResultType.linear,
        difficulty: Difficulty.easy,
        answerLatex: r'x = 4',
        verifyText: 'Check: 2(4) + 5 = 13 ✓ — it matches, so we are correct!',
        tutorIntro: "Nice one! Here's exactly how to solve it — "
            'tap any step to see why it works.',
        steps: const [
          SolutionStep(
            title: 'Start with the equation',
            resultLatex: r'2x + 5 = 13',
            detail: 'This is our puzzle. Right now x is stuck with a + 5 and '
                'a × 2 — we want x all by itself.',
          ),
          SolutionStep(
            title: 'Subtract 5 from both sides',
            operationLabel: '− 5',
            resultLatex: r'2x = 8',
            detail: 'The + 5 is blocking x. Subtracting 5 from BOTH sides '
                'cancels it while keeping the equation balanced.',
          ),
          SolutionStep(
            title: 'Divide both sides by 2',
            operationLabel: '÷ 2',
            resultLatex: r'x = 4',
            detail: '2x means 2 × x. Division undoes multiplication, so '
                'dividing both sides by 2 leaves x completely on its own.',
          ),
        ],
        explanations: const [
          Explanation(
            mode: ExplanationMode.simple,
            body: 'We remove the + 5 first because we want x by itself. Then '
                'we split 2x into a single x by dividing by 2.',
            points: [
              'The + 5 is in the way — take it off both sides',
              '2 lots of x → divide by 2 to get one x',
            ],
          ),
          Explanation(
            mode: ExplanationMode.teacher,
            body: 'Apply inverse operations to isolate the variable: undo '
                'addition with subtraction, then undo multiplication with '
                'division. Whatever you do to one side, do to the other.',
            points: [
              'Inverse of + 5 is − 5',
              'Inverse of × 2 is ÷ 2',
              'Keep both sides balanced at all times',
            ],
          ),
          Explanation(
            mode: ExplanationMode.exam,
            body: 'Subtract 5 from both sides to isolate the variable term, '
                'then divide by the coefficient of x.',
            points: [r'2x + 5 = 13', r'2x = 8', r'x = 4'],
          ),
        ],
        methods: const [
          MethodSolution(
            name: 'Standard Algebra',
            subtitle: 'The balance method',
            description: 'Do the same operation to both sides until x is alone.',
            advantages: [
              'Works for every linear equation',
              'Hard to make mistakes',
            ],
            whenToUse: 'Your reliable go-to for homework and exams.',
            steps: [
              'Subtract 5 from both sides → 2x = 8',
              'Divide both sides by 2 → x = 4',
            ],
            recommended: true,
          ),
          MethodSolution(
            name: 'Transposition',
            subtitle: 'Move across the = sign',
            description: 'Move a term across the equals sign and flip its sign.',
            advantages: ['Fewer lines to write', 'Fast under exam pressure'],
            whenToUse: 'When you are confident handling signs.',
            steps: [
              'Move + 5 across → 2x = 13 − 5 = 8',
              'Move × 2 across → x = 8 ÷ 2 = 4',
            ],
          ),
          MethodSolution(
            name: 'Work Backwards',
            subtitle: 'Undo in reverse order',
            description: 'Reverse each operation that was applied to x.',
            advantages: ['Very intuitive', 'Great for understanding'],
            whenToUse: 'When you want to see the logic behind the steps.',
            steps: [
              'x was × 2 then + 5 to make 13',
              'Reverse it: 13 − 5 = 8, then 8 ÷ 2 = 4',
            ],
          ),
        ],
        practice: const [
          PracticeQuestion(
              questionLatex: r'x + 4 = 9',
              difficulty: Difficulty.easy,
              xpReward: 15),
          PracticeQuestion(
              questionLatex: r'2x + 7 = 15',
              difficulty: Difficulty.easy,
              xpReward: 20),
          PracticeQuestion(
              questionLatex: r'3x + 12 = 30',
              difficulty: Difficulty.medium,
              xpReward: 30),
          PracticeQuestion(
              questionLatex: r'5x - 7 = 18',
              difficulty: Difficulty.medium,
              xpReward: 30),
          PracticeQuestion(
              questionLatex: r'5x + 18 = 48',
              difficulty: Difficulty.hard,
              xpReward: 40),
          PracticeQuestion(
              questionLatex: r'2(x + 3) = 16',
              difficulty: Difficulty.hard,
              xpReward: 45),
        ],
      );

  // ---- Quadratic: x^2 + 5x + 6 = 0 ----
  ResultData _quadratic(DetectedEquation equation) => ResultData(
        equation: equation,
        type: ResultType.quadratic,
        difficulty: Difficulty.medium,
        answerLatex: r'x = -2,\ x = -3',
        verifyText: 'Check: (−2)² + 5(−2) + 6 = 0 ✓',
        tutorIntro: "Let's factor this quadratic — it splits into two neat "
            'brackets.',
        steps: const [
          SolutionStep(
            title: 'Start with the equation',
            resultLatex: r'x^2 + 5x + 6 = 0',
            detail: 'We look for two numbers that multiply to 6 and add to 5.',
          ),
          SolutionStep(
            title: 'Factor the quadratic',
            operationLabel: 'factor',
            resultLatex: r'(x + 2)(x + 3) = 0',
            detail: '2 and 3 multiply to 6 and add to 5, so it factors neatly.',
          ),
          SolutionStep(
            title: 'Use the zero-product rule',
            operationLabel: '= 0',
            resultLatex: r'x + 2 = 0 \ \text{or} \ x + 3 = 0',
            detail: 'If a product is zero, at least one of the factors must '
                'be zero.',
          ),
          SolutionStep(
            title: 'Solve each factor',
            operationLabel: 'solve',
            resultLatex: r'x = -2,\ x = -3',
            detail: 'Subtract to isolate x in each bracket.',
          ),
        ],
        explanations: const [
          Explanation(
            mode: ExplanationMode.simple,
            body: 'We break the quadratic into two brackets that multiply to '
                'give it. If either bracket is zero, the whole thing is zero.',
            points: [
              'Find two numbers: multiply to 6, add to 5',
              'Each bracket = 0 gives an answer',
            ],
          ),
          Explanation(
            mode: ExplanationMode.teacher,
            body: 'Factorise the trinomial, then apply the zero-product '
                'property to obtain the two roots.',
            points: [
              'Product of roots = 6, sum = 5',
              'Factors: (x + 2)(x + 3)',
              'Zero-product property gives x = −2, −3',
            ],
          ),
          Explanation(
            mode: ExplanationMode.exam,
            body: 'Factorise and set each factor to zero.',
            points: [
              r'x^2 + 5x + 6 = 0',
              r'(x + 2)(x + 3) = 0',
              r'x = -2,\ x = -3',
            ],
          ),
        ],
        methods: const [
          MethodSolution(
            name: 'Factoring',
            subtitle: 'Split into brackets',
            description: 'Rewrite as two brackets, then solve each.',
            advantages: ['Fast when it factors', 'No formula to memorise'],
            whenToUse: 'When the numbers factor nicely (most exam questions).',
            steps: [
              'Factor → (x + 2)(x + 3) = 0',
              'Solve each → x = −2, −3',
            ],
            recommended: true,
          ),
          MethodSolution(
            name: 'Quadratic Formula',
            subtitle: 'Always works',
            description: 'Plug a, b, c into the formula for any quadratic.',
            advantages: ['Works even when it will not factor', 'Reliable'],
            whenToUse: 'When factoring is not obvious or the roots are messy.',
            steps: [
              'a = 1, b = 5, c = 6',
              'x = (−5 ± √(25 − 24)) / 2 = −2, −3',
            ],
          ),
          MethodSolution(
            name: 'Completing the Square',
            subtitle: 'Reshape the equation',
            description: 'Turn it into a perfect square to reveal the roots.',
            advantages: ['Builds deep understanding', 'Leads to the formula'],
            whenToUse: 'When you need the vertex or a proof.',
            steps: [
              '(x + 2.5)² = 0.25',
              'x + 2.5 = ±0.5 → x = −2, −3',
            ],
          ),
        ],
        practice: const [
          PracticeQuestion(
              questionLatex: r'x^2 + 4x + 3 = 0',
              difficulty: Difficulty.easy,
              xpReward: 25),
          PracticeQuestion(
              questionLatex: r'x^2 + 7x + 12 = 0',
              difficulty: Difficulty.medium,
              xpReward: 35),
          PracticeQuestion(
              questionLatex: r'2x^2 + 5x - 3 = 0',
              difficulty: Difficulty.hard,
              xpReward: 50),
        ],
      );

  // ---- Fraction: 3/4 + 1/2 ----
  ResultData _fraction(DetectedEquation equation) => ResultData(
        equation: equation,
        type: ResultType.fraction,
        difficulty: Difficulty.easy,
        answerLatex: r'\frac{5}{4}',
        verifyText: 'Check: 5/4 = 1¼ ✓',
        tutorIntro: 'To add fractions we just need the same denominator first.',
        steps: const [
          SolutionStep(
            title: 'Start with the sum',
            resultLatex: r'\frac{3}{4} + \frac{1}{2}',
            detail: 'We can only add fractions when they share a denominator.',
          ),
          SolutionStep(
            title: 'Make the denominators match',
            operationLabel: 'LCD = 4',
            resultLatex: r'\frac{3}{4} + \frac{2}{4}',
            detail: 'Half is the same as 2/4, so now both share denominator 4.',
          ),
          SolutionStep(
            title: 'Add the numerators',
            operationLabel: 'add',
            resultLatex: r'\frac{5}{4}',
            detail: '3/4 + 2/4 = 5/4. We keep the denominator the same.',
          ),
        ],
        explanations: const [
          Explanation(
            mode: ExplanationMode.simple,
            body: 'Fractions only add up when the bottom numbers match. We '
                'change ½ into 2/4, then add the tops.',
            points: ['Same bottom number first', 'Add the tops, keep the bottom'],
          ),
          Explanation(
            mode: ExplanationMode.teacher,
            body: 'Convert to a common denominator using the LCD, then add the '
                'numerators.',
            points: [
              'LCD of 4 and 2 is 4',
              '½ = 2/4',
              '3/4 + 2/4 = 5/4',
            ],
          ),
          Explanation(
            mode: ExplanationMode.exam,
            body: 'Write over a common denominator and add the numerators.',
            points: [r'\frac{3}{4} + \frac{2}{4}', r'\frac{5}{4}'],
          ),
        ],
        methods: const [
          MethodSolution(
            name: 'Common Denominator',
            subtitle: 'Match the bottoms',
            description: 'Rewrite both fractions over the same denominator.',
            advantages: ['Always works', 'Clear and reliable'],
            whenToUse: 'The standard method for adding any fractions.',
            steps: ['½ = 2/4', '3/4 + 2/4 = 5/4'],
            recommended: true,
          ),
          MethodSolution(
            name: 'Cross Multiply',
            subtitle: 'One-line shortcut',
            description: 'a/b + c/d = (ad + bc) / bd in a single step.',
            advantages: ['Fast', 'No LCD hunting'],
            whenToUse: 'When denominators are small and coprime.',
            steps: ['(3×2 + 1×4) / (4×2) = 10/8', 'Simplify → 5/4'],
          ),
          MethodSolution(
            name: 'Decimal Conversion',
            subtitle: 'Switch to decimals',
            description: 'Convert each fraction to a decimal, then add.',
            advantages: ['Easy with a calculator', 'Good sanity check'],
            whenToUse: 'When a decimal answer is acceptable.',
            steps: ['0.75 + 0.5 = 1.25', '1.25 = 5/4'],
          ),
        ],
        practice: const [
          PracticeQuestion(
              questionLatex: r'\frac{1}{3} + \frac{1}{6}',
              difficulty: Difficulty.easy,
              xpReward: 15),
          PracticeQuestion(
              questionLatex: r'\frac{2}{5} + \frac{1}{2}',
              difficulty: Difficulty.medium,
              xpReward: 30),
          PracticeQuestion(
              questionLatex: r'\frac{5}{6} - \frac{3}{4}',
              difficulty: Difficulty.hard,
              xpReward: 40),
        ],
      );

  // ---- Fallback for other kinds ----
  ResultData _fallback(DetectedEquation equation) => ResultData(
        equation: equation,
        type: ResultType.expression,
        difficulty: Difficulty.easy,
        answerLatex: r'= 14',
        verifyText: 'Check with the order of operations (BODMAS) ✓',
        tutorIntro: "Let's work through this step by step.",
        steps: const [
          SolutionStep(
            title: 'Start with the expression',
            resultLatex: r'2 + 3 \times 4',
            detail: 'Multiplication comes before addition (order of '
                'operations).',
          ),
          SolutionStep(
            title: 'Multiply first',
            operationLabel: '×',
            resultLatex: r'2 + 12',
            detail: '3 × 4 = 12, so replace that part first.',
          ),
          SolutionStep(
            title: 'Then add',
            operationLabel: '+',
            resultLatex: r'14',
            detail: '2 + 12 = 14.',
          ),
        ],
        explanations: const [
          Explanation(
            mode: ExplanationMode.simple,
            body: 'Do the times before the plus — that is the rule.',
            points: ['Multiply first', 'Then add'],
          ),
          Explanation(
            mode: ExplanationMode.teacher,
            body: 'Follow the order of operations (BODMAS/BIDMAS): brackets, '
                'orders, division/multiplication, then addition/subtraction.',
            points: ['× before +', '3 × 4 = 12', '2 + 12 = 14'],
          ),
          Explanation(
            mode: ExplanationMode.exam,
            body: 'Apply BODMAS: multiplication precedes addition.',
            points: [r'2 + 3 \times 4', r'2 + 12', r'14'],
          ),
        ],
        methods: const [
          MethodSolution(
            name: 'Order of Operations',
            subtitle: 'BODMAS',
            description: 'Evaluate in the correct priority order.',
            advantages: ['Universal rule', 'Prevents mistakes'],
            whenToUse: 'Any arithmetic expression.',
            steps: ['3 × 4 = 12', '2 + 12 = 14'],
            recommended: true,
          ),
        ],
        practice: const [
          PracticeQuestion(
              questionLatex: r'5 + 2 \times 3',
              difficulty: Difficulty.easy,
              xpReward: 15),
          PracticeQuestion(
              questionLatex: r'(4 + 2) \times 3',
              difficulty: Difficulty.medium,
              xpReward: 25),
        ],
      );
}

/// Provides the active [SolverService]: the real Cloud-Function solver for
/// signed-in users with Firebase configured, else the offline mock (so guests
/// and the unconfigured checkout keep working).
final Provider<SolverService> solverServiceProvider =
    Provider<SolverService>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) return const MockSolverService();
  final functions = ref.watch(firebaseFunctionsProvider);
  return FunctionsSolverService(
    (name, data) => callFunction(functions, name, data),
  );
});
