// Numi's structured teaching format — the lesson cards.
//
// The redesign is a READABILITY change: the same verified maths, laid out as a
// teacher would put it on a board (goal → numbered steps → why → the trap →
// the answer) instead of one paragraph of chat prose. So the tests here defend
// two things at once.
//
// 1. The layout. Every section renders when it has content and vanishes when it
//    doesn't, so a framing-only lesson is two cards and not an empty page of
//    headings.
// 2. The firewall. A card is MORE dangerous than a paragraph: an equation alone
//    under a numbered heading, in the app's own typography, reads as something
//    the app checked. The server gate (`tutorLesson.ts`) is what makes that
//    true; the client's job is to never invent a lesson the payload didn't
//    carry, and to hand the model back what it already taught so the next turn
//    doesn't teach it again.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/tutor/application/functions_tutor_service.dart';
import 'package:matheasy/features/tutor/domain/tutor_models.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_lesson_view.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_message_view.dart';
import 'package:matheasy/l10n/app_localizations.dart';

const _lesson = TutorLesson(
  goal: 'Get x on its own.',
  steps: [
    TutorLessonStep(
      title: 'Undo the multiplication',
      explanation: 'Both sides are multiplied by 2, so divide both by 2.',
      equation: r'x = \frac{6}{2}',
    ),
    TutorLessonStep(title: 'Simplify', equation: 'x = 3'),
  ],
  concept: 'Whatever you do to one side, you do to the other.',
  commonMistake: 'Dividing only the left-hand side.',
  finalAnswer: 'x = 3',
);

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('TutorReplyMapper.lesson', () {
    test('reads the full structured lesson off the wire', () {
      final lesson = TutorReplyMapper.lesson({
        'goal': 'Get x on its own.',
        'steps': [
          {
            'title': 'Undo the multiplication',
            'explanation': 'Divide both sides by 2.',
            'equation': r'x = \frac{6}{2}',
          },
        ],
        'concept': 'Balance is preserved.',
        'commonMistake': 'Only dividing one side.',
        'finalAnswer': 'x = 3',
      });

      expect(lesson, isNotNull);
      expect(lesson!.goal, 'Get x on its own.');
      expect(lesson.steps, hasLength(1));
      expect(lesson.steps.single.title, 'Undo the multiplication');
      expect(lesson.steps.single.equation, r'x = \frac{6}{2}');
      expect(lesson.concept, 'Balance is preserved.');
      expect(lesson.commonMistake, 'Only dividing one side.');
      expect(lesson.finalAnswer, 'x = 3');
    });

    test('a turn with no lesson stays a plain chat turn', () {
      expect(TutorReplyMapper.lesson(null), isNull);
      expect(TutorReplyMapper.lesson('a paragraph'), isNull);
      expect(TutorReplyMapper.lesson(<String, dynamic>{}), isNull);
    });

    test('a goal with nothing under it is not a lesson', () {
      // A heading over an empty page is worse than no cards at all.
      expect(
        TutorReplyMapper.lesson({'goal': 'Get x on its own.', 'steps': []}),
        isNull,
      );
    });

    test('keeps a framing-only lesson (Hint mode: no route to the answer)', () {
      final lesson = TutorReplyMapper.lesson({
        'goal': 'Spot which operation is undoing which.',
        'concept': 'Inverse operations peel an equation apart.',
      });

      expect(lesson, isNotNull);
      expect(lesson!.steps, isEmpty);
      expect(lesson.finalAnswer, isNull);
    });

    test('a step with neither title nor words is dropped', () {
      final lesson = TutorReplyMapper.lesson({
        'goal': 'Solve it.',
        'steps': [
          {'equation': 'x = 3'},
          {'title': 'Simplify'},
        ],
      });

      expect(lesson!.steps, hasLength(1));
      expect(lesson.steps.single.title, 'Simplify');
    });

    test('a step with only words is titled from them', () {
      final lesson = TutorReplyMapper.lesson({
        'goal': 'Solve it.',
        'steps': [
          {'explanation': 'Divide both sides by 2.'},
        ],
      });

      expect(lesson!.steps.single.title, 'Divide both sides by 2.');
    });

    test('malformed steps never crash the turn', () {
      final lesson = TutorReplyMapper.lesson({
        'goal': 'Solve it.',
        'steps': ['not a step', 42, null],
        'concept': 'Balance.',
      });

      expect(lesson, isNotNull);
      expect(lesson!.steps, isEmpty);
    });
  });

  group('TutorLesson.transcript', () {
    test('folds the cards back into the words sent up next turn', () {
      const message = TutorMessage(
        id: 1,
        role: TutorRole.assistant,
        text: "Let's isolate x together.",
        lesson: _lesson,
      );

      final transcript = message.transcriptText;

      // The spoken line survives, and so does everything that was rendered
      // beside it — otherwise the next turn re-teaches step one forever.
      expect(transcript, startsWith("Let's isolate x together."));
      expect(transcript, contains('Goal: Get x on its own.'));
      expect(transcript, contains('Step 1: Undo the multiplication'));
      expect(transcript, contains('Step 2: Simplify'));
      expect(transcript, contains('x = 3'));
      expect(transcript, contains('Watch out: Dividing only the left-hand side.'));
    });

    test('a turn without a lesson sends exactly its words', () {
      const message = TutorMessage(
        id: 1,
        role: TutorRole.assistant,
        text: 'What do you think comes next?',
      );

      expect(message.transcriptText, 'What do you think comes next?');
    });
  });

  group('TutorLessonView', () {
    testWidgets('renders every section of a full lesson', (tester) async {
      await tester.pumpWidget(_host(const TutorLessonView(_lesson)));
      await tester.pump();

      expect(find.text('GOAL'), findsOneWidget);
      expect(find.text('Get x on its own.'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Undo the multiplication'), findsOneWidget);
      expect(find.text('WHY THIS WORKS'), findsOneWidget);
      expect(find.text('COMMON MISTAKE'), findsOneWidget);
      expect(find.text('FINAL ANSWER'), findsOneWidget);
    });

    testWidgets('omits the sections a mode withholds', (tester) async {
      // Hint mode: a goal and a concept, no route and no answer. The cards that
      // would give the game away must not merely be empty — they must be gone.
      const framing = TutorLesson(
        goal: 'Spot which operation is undoing which.',
        concept: 'Inverse operations peel an equation apart.',
      );

      await tester.pumpWidget(_host(const TutorLessonView(framing)));
      await tester.pump();

      expect(find.text('GOAL'), findsOneWidget);
      expect(find.text('WHY THIS WORKS'), findsOneWidget);
      expect(find.text('FINAL ANSWER'), findsNothing);
      expect(find.text('COMMON MISTAKE'), findsNothing);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('a step with no equation shows its words alone', (tester) async {
      // The server drops an equation it could not verify and keeps the step's
      // words. That step still has to look like a step.
      const lesson = TutorLesson(
        goal: 'Solve it.',
        steps: [
          TutorLessonStep(
            title: 'Undo the multiplication',
            explanation: 'Divide both sides by 2.',
          ),
        ],
      );

      await tester.pumpWidget(_host(const TutorLessonView(lesson)));
      await tester.pump();

      expect(find.text('Undo the multiplication'), findsOneWidget);
      expect(find.text('Divide both sides by 2.'), findsOneWidget);
    });

    testWidgets('the step number is spoken as a step, not a digit',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const TutorLessonView(_lesson)));
      await tester.pump();

      // "1" read out on its own tells a screen-reader user nothing.
      expect(find.bySemanticsLabel('Step 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Step 2'), findsOneWidget);
      handle.dispose();
    });
  });

  group('TutorMessageView', () {
    testWidgets('draws the lesson under an assistant turn', (tester) async {
      await tester.pumpWidget(_host(
        TutorMessageView(
          message: const TutorMessage(
            id: 1,
            role: TutorRole.assistant,
            text: "Let's isolate x.",
            lesson: _lesson,
          ),
          onSuggestion: (_) {},
          onPracticeStart: () {},
        ),
      ));
      await tester.pump();

      expect(find.byType(TutorLessonView), findsOneWidget);
      expect(find.text('GOAL'), findsOneWidget);
    });

    testWidgets('a turn without a lesson renders exactly as before',
        (tester) async {
      await tester.pumpWidget(_host(
        TutorMessageView(
          message: const TutorMessage(
            id: 1,
            role: TutorRole.assistant,
            text: 'What do you think comes next?',
          ),
          onSuggestion: (_) {},
          onPracticeStart: () {},
        ),
      ));
      await tester.pump();

      expect(find.byType(TutorLessonView), findsNothing);
      expect(find.text('What do you think comes next?'), findsOneWidget);
    });
  });
}
