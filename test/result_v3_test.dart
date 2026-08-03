// V3 — the redesigned Solution experience. Covers the three new sections that
// carry the hierarchy (problem card / answer card / lesson summary) and the two
// rules the redesign is built on: the answer card teaches NOTHING, and the
// summary is capped at three cards.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/teaching_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart'
    show ProblemDifficulty;
import 'package:matheasy/features/result/presentation/widgets/answer_card.dart';
import 'package:matheasy/features/result/presentation/widgets/learn_more_sheet.dart';
import 'package:matheasy/features/result/presentation/widgets/lesson_summary.dart';
import 'package:matheasy/features/result/presentation/widgets/problem_card.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

const _eq = DetectedEquation(
  latex: r'2x + 5 = 13',
  confidence: 0.92,
  source: ScanSource.camera,
  kind: EquationKind.linear,
);

ResultData _result({TeachingLayer? teaching, String verifyText = 'Checked ✓'}) =>
    ResultData(
      equation: _eq,
      type: ResultType.linear,
      difficulty: Difficulty.easy,
      answerLatex: 'x = 4',
      answerPlain: 'x = 4',
      verifyText: verifyText,
      tutorIntro: '',
      steps: const [
        SolutionStep(title: 'Subtract 5', resultLatex: '2x = 8', detail: 'why.'),
      ],
      explanations: const [],
      methods: const [],
      practice: const [],
      teaching: teaching,
    );

/// A teaching layer offering FOUR summary-worthy things — the cap must hold.
TeachingLayer _teaching() => const TeachingLayer(
      depth: 'full',
      honestReason: null,
      header: TeachingHeader(
        category: 'equations',
        subcategory: 'Linear equation',
        difficulty: ProblemDifficulty.secondary,
        learningObjective: 'Isolate x.',
        methodChosen: 'Balance both sides',
        whyMethodChosen: 'One unknown, one operation each way.',
      ),
      overview: ProblemOverview(
        asked: 'Find x.',
        goal: 'Isolate the variable.',
        givens: ['2x + 5 = 13'],
        predictionPrompt: 'Bigger or smaller than 5?',
      ),
      concept: ConceptOverview(body: 'Do the same thing to both sides.',
          definedTerms: []),
      methodRationale: MethodRationale(alternatives: []),
      journey: [],
      translation: null,
      decompositionPlan: null,
      approach: null,
      commonMistakes: [
        CommonMistake(
          mistake: 'Subtracting from only one side.',
          whyTempting: 'It looks tidier.',
          fix: 'Whatever you do left, do right.',
        ),
        CommonMistake(
          mistake: 'Dividing before subtracting.',
          whyTempting: 'The 2 is right there.',
          fix: 'Undo addition first.',
        ),
      ],
      keyTakeaway: KeyTakeaway(
        headline: 'Undo in reverse order.',
        detail: 'Addition first, then multiplication.',
      ),
      practiceLadder: null,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('§1 problem card', () {
    testWidgets('shows the read + its metadata, and nothing else',
        (tester) async {
      await _pump(tester, ProblemCard(result: _result(), onRescan: () {}));

      expect(find.text('Linear Equation'), findsOneWidget);
      // How the read went, as a state — never the raw percentage, which reads
      // as a claim about the answer and isn't one.
      expect(find.text('High confidence'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      // No answer and no teaching leak into the problem card.
      expect(find.text('FINAL ANSWER'), findsNothing);
      expect(find.text('Start Learning'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('§2 answer card', () {
    testWidgets('is the answer plus three utilities — no educational text',
        (tester) async {
      await _pump(
        tester,
        AnswerCard(
          result: _result(teaching: _teaching()),
          saved: false,
          onToggleSave: () {},
          onShare: () {},
          onCopied: () {},
        ),
      );

      expect(find.text('FINAL ANSWER'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
      // Not one word of teaching — that is the whole point of this card.
      expect(find.textContaining('Undo in reverse order'), findsNothing);
      expect(find.textContaining('both sides'), findsNothing);
      expect(find.text('Checked ✓'), findsNothing);
    });

    testWidgets('Copy puts the PLAIN answer on the clipboard', (tester) async {
      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      var toasted = false;
      await _pump(
        tester,
        AnswerCard(
          result: _result(),
          saved: false,
          onToggleSave: () {},
          onShare: () {},
          onCopied: () => toasted = true,
        ),
      );
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, 'x = 4');
      expect(toasted, isTrue);
    });

    testWidgets('the save control reflects saved state', (tester) async {
      await _pump(
        tester,
        AnswerCard(
          result: _result(),
          saved: true,
          onToggleSave: () {},
          onShare: () {},
          onCopied: () {},
        ),
      );
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('Save'), findsNothing);
    });
  });

  group('§5 lesson summary', () {
    testWidgets('is capped at three cards even with more on offer',
        (tester) async {
      await _pump(
        tester,
        LessonSummary(
          result: _result(teaching: _teaching()),
          methodName: 'Balance',
          onReplay: () {},
        ),
      );

      expect(find.text('METHOD USED'), findsOneWidget);
      expect(find.text('REMEMBER THIS'), findsOneWidget);
      expect(find.text('WATCH OUT FOR'), findsOneWidget);
      // The SECOND common mistake is summary overflow — it belongs in
      // "Learn more", not here.
      expect(find.text('Dividing before subtracting.'), findsNothing);
      // The substitution proof rides along as one caption line, not a card.
      expect(find.text('Checked ✓'), findsOneWidget);
      expect(find.text('Replay the lesson'), findsOneWidget);
    });

    testWidgets('falls back to the selected method name without a teaching layer',
        (tester) async {
      await _pump(
        tester,
        LessonSummary(
          result: _result(),
          methodName: 'Balancing both sides',
          onReplay: () {},
        ),
      );
      expect(find.text('Balancing both sides'), findsOneWidget);
      expect(find.text('REMEMBER THIS'), findsNothing);
    });
  });

  group('learn more', () {
    testWidgets('says so honestly when there is nothing extra', (tester) async {
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => LearnMoreSheet.show(
              context,
              // No teaching, no graph, no alternatives — and only the steps,
              // which the sheet does list.
              result: const ResultData(
                equation: _eq,
                type: ResultType.linear,
                difficulty: Difficulty.easy,
                answerLatex: 'x = 4',
                verifyText: '',
                tutorIntro: '',
                steps: [],
                explanations: [],
                methods: [],
                practice: [],
              ),
              onUseMethod: (_) {},
              onAskMatheasy: () {},
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text("There's nothing extra for this problem yet."),
          findsOneWidget);
    });
  });
}
