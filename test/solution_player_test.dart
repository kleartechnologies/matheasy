// The STATIC "Play Solution" player (Pro Visual-tab content): steps through the
// verified solution one step at a time. Universal — driven by the solve's steps,
// so it works for EVERY problem type, not just schema-carrying equations. No
// animation is asserted here (there is none this phase).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/animation_schema.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/widgets/solution_player.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

const _steps = [
  PlayerStep(
    latex: '2x = 8',
    explanation: 'Subtract 5 from both sides to isolate the x term.',
  ),
  PlayerStep(
    latex: 'x = 4',
    explanation: 'Divide both sides by 2 to solve for x.',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  List<PlayerStep> steps = _steps,
  ValueChanged<int>? onAskStep,
  Size? surface,
}) async {
  if (surface != null) {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SolutionPlayer(steps: steps, onAskStep: onAskStep),
        ),
      ),
    ),
  );
  await tester.pump();
}

DetectedEquation _eq() => const DetectedEquation(
      latex: '2x + 5 = 13',
      confidence: 0.9,
      source: ScanSource.camera,
      kind: EquationKind.linear,
    );

ResultData _result({
  List<SolutionStep> steps = const [],
  AnimationSchema? schema,
}) =>
    ResultData(
      equation: _eq(),
      type: ResultType.linear,
      difficulty: Difficulty.medium,
      answerLatex: 'x = 4',
      steps: steps,
      verifyText: 'checked',
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
      animationSchema: schema,
    );

void main() {
  group('SolutionPlayer widget', () {
    testWidgets('renders the first step, its sentence, and the indicator',
        (tester) async {
      await _pump(tester);
      expect(find.bySemanticsLabel('2x = 8'), findsOneWidget);
      expect(find.bySemanticsLabel('x = 4'), findsNothing);
      expect(find.text('STEP 1 OF 2'), findsOneWidget);
      expect(find.text(_steps[0].explanation), findsOneWidget);
      expect(find.text('Next step'), findsOneWidget);
    });

    testWidgets('Next advances to the last step, then Prev goes back',
        (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Next step'));
      await tester.pump();

      expect(find.bySemanticsLabel('x = 4'), findsOneWidget);
      expect(find.text('SOLVED'), findsOneWidget);
      expect(find.text(_steps[1].explanation), findsOneWidget);
      // Last step offers a replay, not "Next step".
      expect(find.text('Next step'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pump();
      expect(find.text('STEP 1 OF 2'), findsOneWidget);
    });

    testWidgets('shows the "Ask Matheasy" affordance and reports the step index',
        (tester) async {
      int? asked;
      await _pump(tester, onAskStep: (i) => asked = i);
      expect(find.text('Ask Matheasy'), findsOneWidget);
      await tester.tap(find.text('Ask Matheasy'));
      expect(asked, 0);
    });

    testWidgets('token chips render when a step carries tokens', (tester) async {
      await _pump(tester, steps: const [
        PlayerStep(
          latex: '2x = 8',
          explanation: 'why',
          tokens: [
            TokenMapping(
              value: '5',
              fromPath: 'L/1',
              toPath: 'R/1',
              color: TokenColor.pink,
              highlight: TokenHighlight.circle,
            ),
          ],
        ),
        PlayerStep(latex: 'x = 4', explanation: 'why2'),
      ]);
      expect(find.bySemanticsLabel('5'), findsOneWidget);
    });

    testWidgets('does not overflow on a small screen (long expression)',
        (tester) async {
      await _pump(
        tester,
        surface: const Size(320, 480),
        steps: const [
          PlayerStep(
            latex: '3x + 5x - 2 + 7 = 4x + 10 - x',
            explanation: 'Combine the like terms on each side.',
          ),
          PlayerStep(latex: '8x + 5 = 3x + 10', explanation: 'next'),
        ],
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('3x + 5x - 2 + 7 = 4x + 10 - x'),
          findsOneWidget);
    });
  });

  group('buildPlayerSteps (universal — all problem types)', () {
    test('drives steps from the verified solve, with no schema', () {
      final result = _result(steps: const [
        SolutionStep(
          title: 'Differentiate',
          resultLatex: r"f'(x) = 2x",
          detail: 'Apply the power rule to each term.',
        ),
        SolutionStep(title: 'Result', resultLatex: r'2x', detail: ''),
      ]);
      final steps = buildPlayerSteps(result);
      expect(steps, hasLength(2));
      expect(steps[0].latex, r"f'(x) = 2x");
      expect(steps[0].explanation, 'Apply the power rule to each term.');
      // Empty detail falls back to the operation label — never empty/raw.
      expect(steps[1].explanation, 'Result');
      expect(steps[0].tokens, isEmpty); // no schema on this (calculus) path
    });

    test('overlays the animationSchema token chips by step index', () {
      final schema = AnimationSchema.fromJson([
        {
          'stepIndex': 0,
          'changeType': 'SUBTRACT_FROM_BOTH_SIDES',
          'beforeLatex': '2x + 5 = 13',
          'afterLatex': '2x = 8',
          'animationTemplate': 'move_across_equals',
          'tokens': [
            {
              'value': '5',
              'fromPath': 'L/1',
              'toPath': 'R/1',
              'color': 'pink',
              'highlight': 'circle',
            },
          ],
          'explanationKey': 'anim.step.SUBTRACT_FROM_BOTH_SIDES',
        },
      ]);
      final result = _result(
        steps: const [
          SolutionStep(title: 'Subtract', resultLatex: '2x = 8', detail: 'why'),
          SolutionStep(title: 'Divide', resultLatex: 'x = 4', detail: 'why2'),
        ],
        schema: schema,
      );
      final steps = buildPlayerSteps(result);
      expect(steps[0].tokens, hasLength(1)); // schema token overlaid on step 0
      expect(steps[0].tokens.single.value, '5');
      expect(steps[1].tokens, isEmpty); // no schema instruction for step 1
    });

    test('skips steps with an empty expression', () {
      final result = _result(steps: const [
        SolutionStep(title: 'Start', resultLatex: '', detail: 'blank'),
        SolutionStep(title: 'Answer', resultLatex: 'x = 4', detail: 'done'),
      ]);
      final steps = buildPlayerSteps(result);
      expect(steps, hasLength(1));
      expect(steps.single.latex, 'x = 4');
    });
  });
}
