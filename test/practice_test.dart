// Stage 8 tests — the Practice engine.
//
// Covers answer validation, the XP/level + mastery math, the session flow
// controller, session completion → progress (XP/mastery/streak), and local
// persistence round-trips. A fixed practice service keeps everything
// deterministic and offline.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/practice/application/practice_controller.dart';
import 'package:matheasy/features/practice/application/practice_progress_controller.dart';
import 'package:matheasy/features/practice/application/practice_repository.dart';
import 'package:matheasy/features/practice/application/practice_service.dart';
import 'package:matheasy/features/practice/domain/mastery.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_progress.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_session.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/practice/domain/skill_mastery.dart';
import 'package:matheasy/features/practice/domain/xp_level.dart';
import 'package:matheasy/features/practice/presentation/practice_screen.dart';
import 'package:matheasy/features/practice/presentation/practice_session_screen.dart';
import 'package:matheasy/features/subscription/application/subscription_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _inputQ = PracticeQuestion(
  id: 'q-in',
  topic: PracticeTopic.algebra,
  difficulty: PracticeDifficulty.easy,
  type: PracticeQuestionType.input,
  prompt: 'What is 2 + 2?',
  acceptedAnswers: ['4'],
  explanation: '2 + 2 = 4.',
);

const _mcQ = PracticeQuestion(
  id: 'q-mc',
  topic: PracticeTopic.algebra,
  difficulty: PracticeDifficulty.hard,
  type: PracticeQuestionType.multipleChoice,
  prompt: 'Pick the value of x',
  options: [PracticeOption('1'), PracticeOption('3', isCorrect: true)],
  explanation: 'x is 3.',
);

/// A skill-tagged question (Stage 15) — drives per-skill mastery.
const _skillQ = PracticeQuestion(
  id: 'q-skill',
  topic: PracticeTopic.algebra,
  difficulty: PracticeDifficulty.medium,
  type: PracticeQuestionType.input,
  prompt: 'Solve for x',
  acceptedAnswers: ['5'],
  explanation: 'x = 5.',
  skillId: 'alg_linear_1',
);

/// A practice service that returns a fixed question list — deterministic and
/// instant (no mock delay).
class _FixedPracticeService implements PracticeService {
  const _FixedPracticeService(this.questions);

  final List<PracticeQuestion> questions;

  @override
  Future<PracticeSession> createSession(PracticeRequest request) async =>
      PracticeSession(request: request, questions: questions);
}

Future<ProviderContainer> _container({PracticeService? service}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      // The Practice dashboard's difficulty picker reads isPro at build.
      isProProvider.overrideWithValue(false),
      if (service != null)
        practiceServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void _activate(ProviderContainer container) {
  container.listen(practiceControllerProvider, (_, _) {});
  container.listen(practiceProgressControllerProvider, (_, _) {});
}

PracticeAnswer _answer(PracticeQuestion q, {required bool correct}) =>
    PracticeAnswer(
      questionId: q.id,
      submitted: correct ? q.correctAnswerText : 'wrong',
      isCorrect: correct,
      xpEarned: correct ? q.xpReward : 0,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('Answer validation', () {
    test('multiple choice matches the correct option', () {
      expect(_mcQ.evaluate('3'), isTrue);
      expect(_mcQ.evaluate('1'), isFalse);
    });

    test('input normalizes whitespace and assignment', () {
      const q = PracticeQuestion(
        id: 'e',
        topic: PracticeTopic.algebra,
        difficulty: PracticeDifficulty.medium,
        type: PracticeQuestionType.equation,
        prompt: 'Solve for x',
        acceptedAnswers: ['5', 'x=5'],
        explanation: '',
      );
      expect(q.evaluate('5'), isTrue);
      expect(q.evaluate('  x = 5 '), isTrue);
      expect(q.evaluate('x=5'), isTrue);
      expect(q.evaluate('6'), isFalse);
      expect(q.evaluate(''), isFalse);
    });

    test('input accepts currency-prefixed answers', () {
      const q = PracticeQuestion(
        id: 'c',
        topic: PracticeTopic.wordProblems,
        difficulty: PracticeDifficulty.medium,
        type: PracticeQuestionType.input,
        prompt: 'What do 5 tickets cost?',
        acceptedAnswers: ['20'],
        explanation: '',
      );
      expect(q.evaluate(r'$20'), isTrue);
      expect(q.evaluate('20'), isTrue);
    });
  });

  group('XP + mastery math', () {
    test('difficulty carries the spec XP values', () {
      expect(PracticeDifficulty.easy.baseXp, 10);
      expect(PracticeDifficulty.medium.baseXp, 20);
      expect(PracticeDifficulty.hard.baseXp, 40);
    });

    test('XP levels use an increasing curve', () {
      expect(XpLevel.fromTotalXp(0).level, 1);
      expect(XpLevel.fromTotalXp(99).level, 1);
      expect(XpLevel.fromTotalXp(100).level, 2); // level 1 costs 100
      expect(XpLevel.fromTotalXp(250).level, 3); // + level 2 costs 150
    });

    test('mastery level derives from points', () {
      expect(MasteryLevel.forPoints(0), MasteryLevel.beginner);
      expect(MasteryLevel.forPoints(29), MasteryLevel.beginner);
      expect(MasteryLevel.forPoints(30), MasteryLevel.developing);
      expect(MasteryLevel.forPoints(70), MasteryLevel.proficient);
      expect(MasteryLevel.forPoints(100), MasteryLevel.mastered);
    });
  });

  group('PracticeController session flow', () {
    test('runs build → answer → feedback → next → complete', () async {
      final container = await _container(
        service: const _FixedPracticeService([_inputQ, _mcQ]),
      );
      _activate(container);
      final controller = container.read(practiceControllerProvider.notifier);

      await controller.start(const PracticeRequest(topic: PracticeTopic.algebra));
      expect(container.read(practiceControllerProvider).isAnswering, isTrue);
      expect(
        container.read(practiceControllerProvider).session!.currentQuestion.id,
        'q-in',
      );

      controller.submit('4');
      var state = container.read(practiceControllerProvider);
      expect(state.isRevealed, isTrue);
      expect(state.lastWasCorrect, isTrue);
      expect(state.lastAnswer!.xpEarned, 10);

      controller.next();
      expect(
        container.read(practiceControllerProvider).session!.currentQuestion.id,
        'q-mc',
      );

      controller.submit('1'); // wrong
      state = container.read(practiceControllerProvider);
      expect(state.lastWasCorrect, isFalse);
      expect(state.lastAnswer!.xpEarned, 0);

      controller.next();
      state = container.read(practiceControllerProvider);
      expect(state.isComplete, isTrue);
      expect(state.result!.total, 2);
      expect(state.result!.correct, 1);
      expect(state.result!.xpEarned, 10); // only the correct easy answer
    });

    test('submit is ignored unless awaiting an answer', () async {
      final container = await _container(
        service: const _FixedPracticeService([_inputQ]),
      );
      _activate(container);
      final controller = container.read(practiceControllerProvider.notifier);
      await controller.start(const PracticeRequest(topic: PracticeTopic.algebra));

      controller.submit('4');
      controller.submit('4'); // second submit ignored (already revealed)
      expect(
        container.read(practiceControllerProvider).session!.answers,
        hasLength(1),
      );
    });
  });

  group('Session completion → progress', () {
    test('records XP, mastery and topic stats', () async {
      final container = await _container();
      _activate(container);
      final progress = container.read(practiceProgressControllerProvider.notifier);

      final session = PracticeSession(
        request: const PracticeRequest(topic: PracticeTopic.algebra),
        questions: const [_inputQ, _mcQ],
        currentIndex: 1,
        answers: [
          _answer(_inputQ, correct: true), // easy: +10 XP, +2 mastery
          _answer(_mcQ, correct: true), // hard: +40 XP, +5 mastery
        ],
      );
      final result = progress.recordSession(session, now: DateTime(2026));

      expect(result.xpEarned, 50);
      expect(result.correct, 2);
      final state = container.read(practiceProgressControllerProvider);
      expect(state.totalXp, 50);
      expect(state.topic(PracticeTopic.algebra).masteryPoints, 7);
      expect(state.topic(PracticeTopic.algebra).answered, 2);
      expect(state.lastRequest!.topic, PracticeTopic.algebra);
    });

    test('records per-skill mastery for skill-tagged questions (Stage 15)',
        () async {
      final container = await _container();
      _activate(container);
      final progress =
          container.read(practiceProgressControllerProvider.notifier);

      final session = PracticeSession(
        request: const PracticeRequest(topic: PracticeTopic.algebra),
        questions: const [_skillQ],
        answers: [_answer(_skillQ, correct: true)], // medium: +3 skill mastery
      );
      progress.recordSession(session, now: DateTime(2026, 7, 8));

      final mastery =
          container.read(practiceProgressControllerProvider).skills['alg_linear_1'];
      expect(mastery, isNotNull);
      expect(mastery!.attempts, 1);
      expect(mastery.correct, 1);
      expect(mastery.masteryPoints, 3);

      // A hand-authored question (no skillId) leaves the skills map untouched.
      final beforeCount =
          container.read(practiceProgressControllerProvider).skills.length;
      progress.recordSession(
        PracticeSession(
          request: const PracticeRequest(topic: PracticeTopic.algebra),
          questions: const [_inputQ],
          answers: [_answer(_inputQ, correct: true)],
        ),
        now: DateTime(2026, 7, 9),
      );
      expect(
        container.read(practiceProgressControllerProvider).skills.length,
        beforeCount,
      );
    });

    test('daily challenge adds the +100 bonus once per day', () async {
      final container = await _container();
      _activate(container);
      final progress = container.read(practiceProgressControllerProvider.notifier);

      final session = PracticeSession(
        request: PracticeRequest.dailyChallenge(),
        questions: const [_inputQ],
        answers: [_answer(_inputQ, correct: true)],
      );
      final first = progress.recordSession(session, now: DateTime(2026));
      expect(first.xpEarned, 10 + 100);

      // Replaying the daily challenge the same day does NOT re-award the bonus.
      final second = progress.recordSession(session, now: DateTime(2026));
      expect(second.xpEarned, 10);
    });

    test('mastery levels up as points accumulate', () async {
      final container = await _container();
      _activate(container);
      final progress = container.read(practiceProgressControllerProvider.notifier);

      // 6 hard-correct answers = 30 mastery points → Developing.
      final answers = [for (var i = 0; i < 6; i++) _answer(_mcQ, correct: true)];
      final session = PracticeSession(
        request: const PracticeRequest(topic: PracticeTopic.algebra),
        questions: const [_mcQ],
        answers: answers,
      );
      final result = progress.recordSession(session, now: DateTime(2026));
      expect(result.masteryPointsAfter, 30);
      expect(result.masteryAfter, MasteryLevel.developing);
      expect(result.leveledUp, isTrue);
    });

    test('streak increments on consecutive days and resets after a gap',
        () async {
      final container = await _container();
      _activate(container);
      final progress = container.read(practiceProgressControllerProvider.notifier);
      final session = PracticeSession(
        request: const PracticeRequest(topic: PracticeTopic.algebra),
        questions: const [_inputQ],
        answers: [_answer(_inputQ, correct: true)],
      );

      progress.recordSession(session, now: DateTime(2026));
      expect(container.read(practiceProgressControllerProvider).streakCurrent, 1);

      progress.recordSession(session, now: DateTime(2026)); // same day
      expect(container.read(practiceProgressControllerProvider).streakCurrent, 1);

      progress.recordSession(session, now: DateTime(2026, 1, 2)); // next day
      expect(container.read(practiceProgressControllerProvider).streakCurrent, 2);

      progress.recordSession(session, now: DateTime(2026, 1, 9)); // big gap
      expect(container.read(practiceProgressControllerProvider).streakCurrent, 1);
    });
  });

  group('Local persistence', () {
    test('repository round-trips progress including topics + last request',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalPracticeRepository(PreferencesStore(prefs));

      const progress = PracticeProgress(
        totalXp: 120,
        streakCurrent: 3,
        streakBest: 5,
        lastPracticedEpochDay: 20000,
        topics: {
          PracticeTopic.algebra: TopicProgress(
            topic: PracticeTopic.algebra,
            masteryPoints: 40,
            answered: 12,
            correct: 9,
          ),
        },
        lastRequest: PracticeRequest(
          topic: PracticeTopic.fractions,
          difficulty: PracticeDifficulty.hard,
        ),
      );
      await repository.save(progress);

      final loaded = repository.load();
      expect(loaded.totalXp, 120);
      expect(loaded.streakCurrent, 3);
      expect(loaded.streakBest, 5);
      expect(loaded.topic(PracticeTopic.algebra).masteryPoints, 40);
      expect(loaded.topic(PracticeTopic.algebra).correct, 9);
      expect(loaded.lastRequest!.topic, PracticeTopic.fractions);
      expect(loaded.lastRequest!.difficulty, PracticeDifficulty.hard);
    });

    test('repository round-trips skill mastery and adaptive request (Stage 15)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalPracticeRepository(PreferencesStore(prefs));

      const progress = PracticeProgress(
        totalXp: 30,
        skills: {
          'alg_linear_1': SkillMastery(
            skillId: 'alg_linear_1',
            masteryPoints: 12,
            attempts: 4,
            correct: 3,
            lastSeenEpochDay: 20000,
          ),
        },
        lastRequest: PracticeRequest(
          topic: PracticeTopic.algebra,
          skillId: 'alg_linear_1',
          adaptive: true,
        ),
      );
      await repository.save(progress);

      final loaded = repository.load();
      final skill = loaded.skills['alg_linear_1']!;
      expect(skill.masteryPoints, 12);
      expect(skill.attempts, 4);
      expect(skill.correct, 3);
      expect(skill.lastSeenEpochDay, 20000);
      expect(loaded.lastRequest!.skillId, 'alg_linear_1');
      expect(loaded.lastRequest!.adaptive, isTrue);
    });

    test('corrupt payload falls back to empty', () async {
      SharedPreferences.setMockInitialValues({'practice.progress': 'not json'});
      final prefs = await SharedPreferences.getInstance();
      final repository = LocalPracticeRepository(PreferencesStore(prefs));
      expect(repository.load().totalXp, 0);
    });
  });

  group('Widget smoke', () {
    testWidgets('dashboard renders the header and a category', (tester) async {
      // Tall viewport so every section (incl. the difficulty picker now above
      // the topic lists) lays out at once — the scroll below then finds a
      // category immediately without the zero-then-many finder race.
      tester.view.physicalSize = const Size(1200, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = await _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PracticeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Practice'), findsOneWidget);
      await tester.scrollUntilVisible(
        // 'Algebra' appears in both "Recommended" and "All topics"; the first is
        // on-screen in the tall viewport, so this resolves immediately.
        find.text('Algebra').first,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Algebra'), findsWidgets);
    });

    testWidgets('session grades an answer and shows feedback', (tester) async {
      final container = await _container(
        service: const _FixedPracticeService([_inputQ]),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const PracticeSessionScreen(
              request: PracticeRequest(topic: PracticeTopic.algebra),
            ),
          ),
        ),
      );
      await tester.pump(); // run post-frame start()
      await tester.pump();

      expect(find.text('What is 2 + 2?'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '4');
      await tester.pump();
      await tester.tap(find.text('Check answer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('2 + 2 = 4.'), findsOneWidget); // explanation shown
      expect(find.text('See results'), findsOneWidget); // last question
    });
  });
}
