// Step 5 — the §4/§5 result stepper: the LaTeX step-diff emphasis, the method
// switcher, and the verified:false honest state.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/application/solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/result_screen.dart';
import 'package:matheasy/features/result/presentation/tabs/solution_tab.dart';
import 'package:matheasy/features/result/presentation/widgets/math_text.dart';
import 'package:matheasy/features/result/presentation/widgets/result_couldnt_verify.dart';
import 'package:matheasy/features/result/presentation/widgets/result_graph.dart';
import 'package:matheasy/features/result/presentation/widgets/step_diff.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

/// A solver that always returns a `verified:false` (couldn't-verify) result.
class _UnverifiedSolver implements SolverService {
  @override
  Future<ResultData> solve(DetectedEquation equation) async => ResultData(
        equation: equation,
        type: ResultType.trigonometry,
        difficulty: Difficulty.medium,
        answerLatex: '',
        verified: false,
        verifyText: "couldn't verify",
        tutorIntro: '',
        steps: const [],
        explanations: const [],
        methods: const [],
        practice: const [],
      );
}

const _eq = DetectedEquation(
  latex: r'5x^2 + 3x - 2 = 0',
  confidence: 0.95,
  source: ScanSource.camera,
  kind: EquationKind.quadratic,
);

SolutionStep _step(String title, String latex) =>
    SolutionStep(title: title, resultLatex: latex, detail: 'because.');

const _graph = GraphData(
  kind: 'function',
  expression: '5x^2 + 3x - 2',
  keyPoints: [
    GraphKeyPoint(label: 'root', x: -1, y: 0),
    GraphKeyPoint(label: 'vertex', x: -0.3, y: -2.45),
  ],
  curve: [Offset(-2, 12), Offset(-1, 0), Offset(0, -2), Offset(1, 6)],
);

ResultData _twoMethodResult({GraphData? graph}) => ResultData(
      equation: _eq,
      type: ResultType.quadratic,
      difficulty: Difficulty.medium,
      answerLatex: 'x = -1',
      answerPlain: 'x = -1',
      verifyText: 'Checked ✓',
      tutorIntro: "Here's how.",
      graph: graph,
      steps: [_step('Factor', 'A')],
      explanations: const [],
      methods: [
        MethodSolution(
          name: 'Factoring',
          subtitle: '',
          description: '',
          advantages: const [],
          whenToUse: '',
          steps: const ['A'],
          recommended: true,
          stepperSteps: [_step('Factor the quadratic', 'A')],
        ),
        MethodSolution(
          name: 'Formula',
          subtitle: '',
          description: '',
          advantages: const [],
          whenToUse: '',
          steps: const ['B'],
          stepperSteps: [_step('Apply the formula', 'B')],
        ),
      ],
      practice: const [],
    );

void main() {
  group('step-diff (§5 what-changed)', () {
    test('atomize keeps commands and braced groups as single atoms', () {
      expect(atomize(r'\frac{x^{2}}{3}'), [r'\frac{x^{2}}{3}']);
      expect(atomize(r'\sqrt{x+1}'), [r'\sqrt{x+1}']);
      expect(atomize('x^{2}'), ['x^{2}']); // base + script stay together
      expect(atomize('2x'), ['2', 'x']);
    });

    test('emphasizeChanged isolates a single contiguous change', () {
      expect(
        emphasizeChanged('2x + 5 = 15', '2x = 10', colorHex: '#10B981'),
        r'2x \textcolor{#10B981}{= 10}',
      );
      // Factoring: the "= 0" suffix is shared, the factored form is highlighted.
      expect(
        emphasizeChanged('x^{2} + 5x + 6 = 0', '(x + 2)(x + 3) = 0',
            colorHex: '#10B981'),
        r'\textcolor{#10B981}{(x + 2)(x + 3)} = 0',
      );
    });

    test('returns null (→ whole-line fallback) with no isolable change', () {
      expect(emphasizeChanged('x = 5', 'x = 5', colorHex: '#c'), isNull);
      expect(emphasizeChanged('', 'x = 5', colorHex: '#c'), isNull);
      // multi-site change (both sides) → no shared prefix/suffix
      expect(emphasizeChanged('2x = 10', 'x = 5', colorHex: '#c'), isNull);
      // whole fraction atom changed
      expect(
        emphasizeChanged(r'\frac{x}{3}', r'\frac{x}{9}', colorHex: '#c'),
        isNull,
      );
    });

    testWidgets('the \\textcolor emphasis renders as math (no raw fallback)',
        (tester) async {
      const emphasized = r'2x \textcolor{#10B981}{= 8}';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MathText(emphasized, style: TextStyle(fontSize: 20)),
          ),
        ),
      );
      await tester.pump();
      // MathText falls back to a Text of the raw string on a parse error; its
      // absence confirms flutter_math rendered the coloured span.
      expect(find.text(emphasized), findsNothing);
    });
  });

  group('method switcher (§5)', () {
    testWidgets('switching method drives its own stepper', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: SolutionTab(result: _twoMethodResult()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Both method chips are present; method 0's step shows first.
      expect(find.text('Factoring'), findsOneWidget);
      expect(find.text('Formula'), findsOneWidget);
      expect(find.text('Factor the quadratic'), findsOneWidget);
      expect(find.text('Apply the formula'), findsNothing);

      // Select the other method → its stepper renders.
      await tester.tap(find.text('Formula'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Apply the formula'), findsOneWidget);
      expect(find.text('Factor the quadratic'), findsNothing);
    });
  });

  group('graph (§7)', () {
    testWidgets('is an expander, collapsed by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: ResultGraphSection(graph: _graph)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Graph'), findsOneWidget);
      expect(find.text('Show'), findsOneWidget);
      expect(find.text('Hide'), findsNothing);

      await tester.tap(find.text('Graph'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Hide'), findsOneWidget); // now expanded
    });

    testWidgets('Solution tab shows the graph section only when graph != null',
        (tester) async {
      Future<void> pump(ResultData r) => tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: SingleChildScrollView(child: SolutionTab(result: r)),
              ),
            ),
          );

      await pump(_twoMethodResult(graph: _graph));
      await tester.pump();
      expect(find.text('Graph'), findsOneWidget);

      await pump(_twoMethodResult()); // graph == null
      await tester.pump();
      expect(find.text('Graph'), findsNothing); // no empty box
    });
  });

  group('verified:false honest state (§1.1 / §9)', () {
    testWidgets('shows no answer, only the honest state + a way forward',
        (tester) async {
      var rescanned = false;
      var edited = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ResultCouldntVerify(
                result: _twoMethodResult(),
                onRescan: () => rescanned = true,
                onEdit: () => edited = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text("COULDN'T VERIFY"), findsOneWidget);
      expect(find.text('FINAL ANSWER'), findsNothing); // never a confident answer
      // The problem is shown so a misread can be fixed; no confident answer.
      expect(find.text('WHAT I READ'), findsOneWidget);
      await tester.tap(find.text('Rescan'));
      await tester.tap(find.text('Edit the problem'));
      expect(rescanned, isTrue);
      expect(edited, isTrue);
    });

    testWidgets('ResultScreen routes a verified:false solve to the honest state',
        (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            solverServiceProvider.overrideWithValue(_UnverifiedSolver()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ResultScreen(equation: _eq),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600)); // solve

      // The honest state — no answer, no tabs.
      expect(find.text("COULDN'T VERIFY"), findsOneWidget);
      expect(find.text('FINAL ANSWER'), findsNothing);
      expect(find.text('Methods'), findsNothing); // no tab strip
    });
  });
}
