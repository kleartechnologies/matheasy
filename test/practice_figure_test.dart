// Stage 3 — practice render path: a question can carry an optional figure that
// renders above the prompt, and (THE TRAP) the figure survives .withId()
// restamping. Nothing populates `figure` until Stage 4, so these tests build one
// by hand — the visual payoff is deferred, the wiring is proven here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_figure.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/practice/presentation/widgets/practice_figure_view.dart';
import 'package:matheasy/features/practice/presentation/widgets/practice_question_view.dart';

const _triangle = PracticeFigure(
  kind: PracticeFigureKind.polygon,
  semanticsLabel: 'A triangle with angles 86°, 37° and 57°.',
  vertices: [
    PracticeFigurePoint(0, 0),
    PracticeFigurePoint(4, 0),
    PracticeFigurePoint(2, 3),
  ],
  vertexLabels: ['A', 'B', 'C'],
  angleLabels: ['86°', '37°', '57°'],
  sideLabels: ['5 cm', '', ''],
);

PracticeQuestion _question({PracticeFigure? figure}) => PracticeQuestion(
      id: 'q1',
      topic: PracticeTopic.geometry,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.input,
      prompt: 'Find the third angle.',
      explanation: '180 − 86 − 37 = 57.',
      acceptedAnswers: const ['57'],
      figure: figure,
    );

void main() {
  group('PracticeQuestion.figure + withId (the silent-drop trap)', () {
    test('a figure survives .withId() restamp', () {
      final q = _question(figure: _triangle);
      final restamped = q.withId('slot-7');
      expect(restamped.id, 'slot-7');
      // If withId() forgot `figure: figure`, this would be null — no error, just
      // a figure that silently never appears. This test is the safety net.
      expect(restamped.figure, same(_triangle));
    });

    test('a null figure stays null through withId()', () {
      expect(_question().withId('slot-1').figure, isNull);
    });
  });

  group('PracticeQuestionView figure rendering', () {
    testWidgets('renders the figure above the prompt, described for a11y',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: PracticeQuestionView(question: _question(figure: _triangle)),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PracticeFigureView), findsOneWidget);
      expect(find.text('Find the third angle.'), findsOneWidget); // prompt intact
      // A screen-reader user gets the figure described (an unlabelled canvas is
      // invisible to them).
      expect(
        find.bySemanticsLabel('A triangle with angles 86°, 37° and 57°.'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('no figure → no figure widget (nullable, existing questions '
        'unaffected)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: PracticeQuestionView(question: _question())),
        ),
      );
      await tester.pump();
      expect(find.byType(PracticeFigureView), findsNothing);
      expect(find.text('Find the third angle.'), findsOneWidget);
    });
  });
}
