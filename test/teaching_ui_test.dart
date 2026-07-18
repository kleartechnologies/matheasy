// Phase 3 — the Learning Journey UX. Renders SolutionTab with a teaching layer
// and asserts: the teaching cards appear; a v1 (teaching==null) payload renders
// NONE of them (back-compat); the pivotal self-explain + deeper step fields show;
// an out-of-range journey index can't crash; nothing overflows at phone width.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/teaching_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart'
    show ProblemDifficulty;
import 'package:matheasy/features/result/presentation/tabs/solution_tab.dart';
import 'package:matheasy/features/result/presentation/widgets/teaching/teaching_cards.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

const _eq = DetectedEquation(
  latex: 'x^2 - 5x + 6 = 0',
  confidence: 0.98,
  source: ScanSource.camera,
  kind: EquationKind.quadratic,
);

const _steps = [
  SolutionStep(
    title: 'Start with the equation',
    resultLatex: 'x^2 - 5x + 6 = 0',
    detail: 'Begin with the quadratic exactly as given.',
  ),
  SolutionStep(
    title: 'Factor into two brackets',
    resultLatex: '(x - 2)(x - 3) = 0',
    detail: 'Find two numbers that multiply and add correctly.',
    operationLabel: 'factor',
    rule: 'Sum-product factoring',
    commonMistake: 'Choosing the wrong signs.',
    selfExplainPrompt: 'Which pair multiplies to give the constant?',
    pivotal: true,
  ),
];

TeachingLayer _teaching() => const TeachingLayer(
      depth: 'lite',
      honestReason: null,
      header: TeachingHeader(
        category: 'equations',
        subcategory: 'Quadratic equation',
        difficulty: ProblemDifficulty.secondary,
        learningObjective: 'Solve a factorable quadratic with the zero-product rule.',
        methodChosen: 'Factoring',
        whyMethodChosen: 'The constant factors into small whole numbers.',
      ),
      overview: ProblemOverview(
        asked: 'Find every value of x that makes it zero.',
        goal: 'Rewrite as a product, then set each factor to zero.',
        givens: ['x^2 - 5x + 6 = 0'],
        predictionPrompt: 'One answer, two, or none?',
      ),
      concept: ConceptOverview(
        body: 'A quadratic is an equation where the variable is squared; its '
            'graph is a U-shaped curve whose crossing points are the answers.',
        definedTerms: [
          DefinedTerm(term: 'root', plain: 'a value of x that makes it zero'),
        ],
      ),
      methodRationale: MethodRationale(alternatives: []),
      journey: [
        JourneyStage(
            id: JourneyStageId.understand, summary: null, stepIndices: []),
        JourneyStage(id: JourneyStageId.apply, summary: null, stepIndices: [1]),
        // Deliberately out-of-range: the rail must clamp, never index steps[99].
        JourneyStage(
            id: JourneyStageId.simplify, summary: null, stepIndices: [99]),
      ],
      translation: null,
      decompositionPlan: null,
      approach: null,
      commonMistakes: [
        CommonMistake(
          mistake: 'Getting the signs of the factors wrong.',
          whyTempting: 'Both roots are positive.',
          fix: 'Expand the brackets back and check the middle term.',
        ),
      ],
      keyTakeaway: KeyTakeaway(
        headline: 'See a factorable quadratic? Factor, then zero each bracket.',
        detail: 'The roots fall straight out.',
      ),
      practiceLadder: PracticeLadder(
        easier: PracticeItem(
            latex: 'x^2 - 3x + 2 = 0', plain: null, rung: 'easier', skillHint: null),
        similar: PracticeItem(
            latex: 'x^2 - 7x + 12 = 0', plain: null, rung: 'similar', skillHint: null),
        harder: PracticeItem(
            latex: '2x^2 - 7x + 3 = 0', plain: null, rung: 'harder', skillHint: null),
      ),
    );

ResultData _result({TeachingLayer? teaching}) => ResultData(
      equation: _eq,
      type: ResultType.quadratic,
      difficulty: Difficulty.medium,
      answerLatex: 'x = 2 or x = 3',
      steps: _steps,
      verifyText: 'Checked by substitution',
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
      teaching: teaching,
    );

Future<void> _pump(WidgetTester tester, ResultData result,
    {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(360, 3200); // narrow + tall
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SolutionTab(
            result: result,
            onOpenMethods: () {},
            onAskMatheasy: () {},
            onAttemptPractice: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _hasRich(WidgetTester tester, String needle) => tester
    .widgetList<RichText>(find.byType(RichText))
    .any((r) => r.text.toPlainText().contains(needle));

void main() {
  testWidgets('renders the teaching cards for a v2 payload', (tester) async {
    await _pump(tester, _result(teaching: _teaching()));

    // Header + objective, concept, why-method, mistakes, takeaway, practice.
    expect(find.text('THE IDEA'), findsOneWidget);
    expect(
      find.textContaining('Solve a factorable quadratic'),
      findsWidgets, // the objective (header) — may also echo in takeaway area
    );
    expect(find.text('Factoring'), findsOneWidget); // why-this-method title
    expect(find.text('WATCH OUT FOR'), findsOneWidget);
    expect(find.text('REMEMBER THIS'), findsOneWidget);
    expect(find.text('YOUR TURN'), findsOneWidget); // practice ladder
    // Journey rail labels.
    expect(find.text('Understand'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    // No overflow anywhere at 360 wide.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a v1 payload (teaching == null) renders NO teaching cards',
      (tester) async {
    await _pump(tester, _result());

    expect(find.text('THE IDEA'), findsNothing);
    expect(find.text('WATCH OUT FOR'), findsNothing);
    expect(find.text('REMEMBER THIS'), findsNothing);
    expect(find.text('YOUR TURN'), findsNothing);
    // The steps still render (byte-identical solution experience).
    expect(find.text('Start with the equation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pivotal step shows the self-explain prompt once revealed',
      (tester) async {
    await _pump(tester, _result(teaching: _teaching()));
    // Reveal the pivotal (2nd) step.
    await tester.tap(find.text('Reveal all'));
    await tester.pumpAndSettle();

    expect(_hasRich(tester, 'Your turn'), isTrue);
    expect(_hasRich(tester, 'Which pair multiplies'), isTrue);
  });

  testWidgets('deeper step fields (rule + common mistake) reveal on "Why?"',
      (tester) async {
    await _pump(tester, _result(teaching: _teaching()));
    await tester.tap(find.text('Reveal all'));
    await tester.pumpAndSettle();

    // The pivotal step is collapsed → its toggle reads "Why?". Tap it.
    expect(find.text('Why?'), findsWidgets);
    await tester.tap(find.text('Why?').last);
    await tester.pumpAndSettle();

    expect(find.text('Sum-product factoring'), findsOneWidget); // the rule chip
    expect(find.text('Choosing the wrong signs.'), findsOneWidget);
  });

  testWidgets('an out-of-range journey index never crashes the rail',
      (tester) async {
    // _teaching() has a Simplify stage pointing at step 99 (only 2 steps exist).
    await _pump(tester, _result(teaching: _teaching()));
    expect(find.text('Simplify'), findsOneWidget); // rendered, as inactive
    expect(tester.takeException(), isNull);
  });

  testWidgets('ApproachCard (honest mode) renders its numbered steps',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ApproachCard(approach: [
            'Recognise this is a proof, not a calculation',
            'Assume the opposite and look for a contradiction',
            'Watch the edge case',
          ]),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('HOW TO APPROACH IT'), findsOneWidget);
    expect(find.text('Assume the opposite and look for a contradiction'),
        findsOneWidget);
    expect(find.text('1'), findsOneWidget); // numbered
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in DARK mode without exception (contrast-fix path)',
      (tester) async {
    await _pump(tester, _result(teaching: _teaching()), theme: AppTheme.dark);
    // The header + practice pills use theme-aware container/on-container tokens
    // (the dark-mode contrast fixes) — exercise that path.
    expect(find.text('THE IDEA'), findsOneWidget);
    expect(find.text('YOUR TURN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
