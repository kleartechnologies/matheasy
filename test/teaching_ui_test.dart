// Phase 3 / V3 — the guided-lesson UX. Renders SolutionTab with a teaching layer
// and asserts: the tab OPENS on a single CTA (the teaching layer never dumps
// onto the page); the optional layers are reachable, collapsed, in "Learn more";
// the pivotal self-explain + deeper step fields show inside the step player; and
// finishing the lesson reveals the summary + practice ladder. Nothing overflows
// at phone width.

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

/// Walks from the opening CTA to the last step of the lesson.
Future<void> _startLesson(WidgetTester tester) async {
  await tester.tap(find.text('Start Learning'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a v2 payload opens on the CTA, not on a wall of teaching cards',
      (tester) async {
    await _pump(tester, _result(teaching: _teaching()));

    // SECTION 3 — one invitation, and one quiet door to everything optional.
    expect(find.text('Start Learning'), findsOneWidget);
    expect(find.text('Learn more'), findsOneWidget);

    // None of the optional layers may be on screen before the lesson starts.
    expect(find.text('The idea'), findsNothing);
    expect(find.text('Watch out for'), findsNothing);
    expect(find.text('Remember this'), findsNothing);
    expect(find.text('YOUR TURN'), findsNothing);
    // Not even the first step — the learner asks for it.
    expect(find.text('Start with the equation'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Learn more" holds every optional layer, each collapsed',
      (tester) async {
    await _pump(tester, _result(teaching: _teaching()));
    await tester.tap(find.text('Learn more'));
    await tester.pumpAndSettle();

    // Section titles are there…
    expect(find.text('The idea'), findsOneWidget);
    expect(find.text('What it asks'), findsOneWidget);
    expect(find.text('Glossary'), findsOneWidget);
    expect(find.text('All steps'), findsOneWidget);
    expect(find.text('Watch out for'), findsOneWidget);
    expect(find.text('Remember this'), findsOneWidget);
    // …but their bodies are not, until asked for.
    expect(find.textContaining('U-shaped curve'), findsNothing);
    await tester.tap(find.text('The idea'));
    await tester.pumpAndSettle();
    expect(find.textContaining('U-shaped curve'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a v1 payload (teaching == null) still walks its steps',
      (tester) async {
    await _pump(tester, _result());
    await _startLesson(tester);

    expect(find.text('Start with the equation'), findsOneWidget);
    // No teaching layer → nothing extra leaks into the lesson.
    expect(find.text('Watch out for'), findsNothing);
    expect(find.text('YOUR TURN'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the spine lists every step but opens only one', (tester) async {
    await _pump(tester, _result(teaching: _teaching()));
    await _startLesson(tester);

    // The map: the whole road is on screen, so the learner always knows how
    // far in they are and what is still coming.
    expect(find.text('Start with the equation'), findsOneWidget);
    expect(find.text('Factor into two brackets'), findsOneWidget);
    // The attention: only the OPEN step offers its reasoning.
    expect(find.text('Explain how'), findsOneWidget);

    // Any row is a destination — reading ahead never costs you your place.
    await tester.tap(find.text('Factor into two brackets'));
    await tester.pumpAndSettle();
    expect(_hasRich(tester, 'Which pair multiplies'), isTrue);
  });

  testWidgets('the pivotal step shows the self-explain prompt', (tester) async {
    await _pump(tester, _result(teaching: _teaching()));
    await _startLesson(tester);
    await tester.tap(find.text('Next step')); // → the pivotal 2nd step
    await tester.pumpAndSettle();

    expect(_hasRich(tester, 'Your turn'), isTrue);
    expect(_hasRich(tester, 'Which pair multiplies'), isTrue);
  });

  testWidgets('deeper step fields reveal on "Explain how"', (tester) async {
    await _pump(tester, _result(teaching: _teaching()));
    await _startLesson(tester);
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();

    // The named rule labels the move up front — it IS the instruction.
    expect(find.text('Sum-product factoring'), findsOneWidget);
    // The trap waits behind one tap.
    expect(find.text('Choosing the wrong signs.'), findsNothing);
    await tester.tap(find.text('Explain how'));
    await tester.pumpAndSettle();
    expect(find.text('Choosing the wrong signs.'), findsOneWidget);
  });

  testWidgets('reaching the Solution row reveals the summary, then practice',
      (tester) async {
    await _pump(tester, _result(teaching: _teaching()));
    await _startLesson(tester);
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next step')); // → the Solution row = the end
    await tester.pumpAndSettle();

    // SECTION 5 — three cards, no more: method used, remember this, watch out.
    expect(find.text('Lesson complete'), findsOneWidget);
    expect(find.text('METHOD USED'), findsOneWidget);
    expect(find.text('REMEMBER THIS'), findsOneWidget);
    expect(find.text('WATCH OUT FOR'), findsOneWidget);
    // SECTION 6 — practice, only now.
    expect(find.text('Now try one yourself'), findsOneWidget);
    expect(find.text('YOUR TURN'), findsOneWidget);
    // SECTION 7 — Numi, last.
    expect(find.text('Still confused?'), findsOneWidget);
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
    await _startLesson(tester);
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next step'));
    await tester.pumpAndSettle();

    // The summary + practice pills use theme-aware container/on-container
    // tokens (the dark-mode contrast fixes) — exercise that path.
    expect(find.text('REMEMBER THIS'), findsOneWidget);
    expect(find.text('YOUR TURN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
