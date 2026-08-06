// The V5 learning-loop state machine: wrong answers land in `retry` (nothing
// recorded), Try Again / hints / solution views accumulate on the live
// QuestionAttempt, and the FINAL answer carries the whole journey — attempts,
// hint level, solution views, injected-clock timing — with XP scaled by how
// independently the student got there (1.0× / 0.7× / 0.5×).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/features/practice/application/practice_controller.dart';
import 'package:matheasy/features/practice/application/practice_progress_controller.dart';
import 'package:matheasy/features/practice/application/practice_service.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_session.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/practice/domain/xp_reward.dart';
import 'package:matheasy/features/progress/application/achievement_service.dart'
    show clockProvider;
import 'package:shared_preferences/shared_preferences.dart';

const _q1 = PracticeQuestion(
  id: 'q1',
  topic: PracticeTopic.algebra,
  difficulty: PracticeDifficulty.easy, // baseXp 10
  type: PracticeQuestionType.input,
  prompt: 'What is 2 + 2?',
  acceptedAnswers: ['4'],
  explanation: '2 + 2 = 4.',
  hints: ['Count it out.', 'Add the two numbers.'],
);

const _q2 = PracticeQuestion(
  id: 'q2',
  topic: PracticeTopic.algebra,
  difficulty: PracticeDifficulty.easy,
  type: PracticeQuestionType.input,
  prompt: 'What is 3 + 3?',
  acceptedAnswers: ['6'],
  explanation: '3 + 3 = 6.',
);

class _FixedPracticeService implements PracticeService {
  const _FixedPracticeService(this.questions);

  final List<PracticeQuestion> questions;

  @override
  Future<PracticeSession> createSession(PracticeRequest request) async =>
      PracticeSession(request: request, questions: questions);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  Future<ProviderContainer> makeContainer({
    List<PracticeQuestion> questions = const [_q1, _q2],
  }) async {
    now = DateTime(2026, 7, 8, 10);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        clockProvider.overrideWithValue(() => now),
        practiceServiceProvider
            .overrideWithValue(_FixedPracticeService(questions)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(practiceControllerProvider, (_, _) {});
    container.listen(practiceProgressControllerProvider, (_, _) {});
    return container;
  }

  Future<PracticeController> start(ProviderContainer container) async {
    final controller = container.read(practiceControllerProvider.notifier);
    await controller
        .start(const PracticeRequest(topic: PracticeTopic.algebra));
    return controller;
  }

  PracticeSessionState state(ProviderContainer c) =>
      c.read(practiceControllerProvider);

  group('retry loop', () {
    test('an incorrect answer lands in retry and records nothing', () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('99');
      final s = state(container);
      expect(s.phase, PracticePhase.retry);
      expect(s.session!.answers, isEmpty);
      expect(s.lastAnswer, isNull);
      expect(s.attempt!.attempts, 1);
      expect(s.attempt!.lastSubmitted, '99');
      expect(s.mistake!.submittedAnswer, '99');
    });

    test('wrong → try again → correct records ONE answer with attempts=2',
        () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('99');
      controller.tryAgain();
      expect(state(container).phase, PracticePhase.answering);

      controller.submit('4');
      final s = state(container);
      expect(s.phase, PracticePhase.revealed);
      expect(s.session!.answers, hasLength(1));
      final answer = s.lastAnswer!;
      expect(answer.isCorrect, isTrue);
      expect(answer.attempts, 2);
      // Retried → 0.7× of easy's base 10.
      expect(answer.xpEarned, XpReward.forOutcome(PracticeDifficulty.easy,
          attempts: 2, hintLevelUsed: 0, viewedSolution: false));
      expect(answer.xpEarned, 7);
    });

    test('submit is ignored once the question is revealed', () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('4');
      expect(state(container).phase, PracticePhase.revealed);
      controller.submit('4');
      expect(state(container).session!.answers, hasLength(1));
    });
  });

  group('XP for learning', () {
    test('first-try clean earns the full base XP', () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('4');
      final answer = state(container).lastAnswer!;
      expect(answer.isFirstTryClean, isTrue);
      expect(answer.xpEarned, 10);
    });

    test('a hint before a first-try correct drops XP to 0.7×', () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.requestHint();
      controller.submit('4');
      final answer = state(container).lastAnswer!;
      expect(answer.hintLevelUsed, 1);
      expect(answer.xpEarned, 7);
    });

    test('viewing the solution drops a later correct to 0.5×', () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('99');
      controller.markSolutionViewed();
      controller.submit('4');
      final answer = state(container).lastAnswer!;
      expect(answer.viewedSolution, isTrue);
      expect(answer.xpEarned, 5);
    });

    test('riding the hint ladder to level 4 also counts as solution-tier',
        () async {
      final container = await makeContainer();
      final controller = await start(container);

      for (var i = 0; i < 6; i++) {
        controller.requestHint(); // capped at 4
      }
      expect(state(container).hintLevel, 4);
      controller.submit('4');
      expect(state(container).lastAnswer!.xpEarned, 5);
    });
  });

  group('giveUp', () {
    test('finalizes the question as incorrect with its journey metadata',
        () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('99');
      controller.requestHint();
      controller.requestHint();
      now = now.add(const Duration(seconds: 42));
      controller.giveUp();

      final s = state(container);
      expect(s.phase, PracticePhase.revealed);
      final answer = s.lastAnswer!;
      expect(answer.isCorrect, isFalse);
      expect(answer.xpEarned, 0);
      expect(answer.attempts, 1);
      expect(answer.hintLevelUsed, 2);
      expect(answer.submitted, '99');
      expect(answer.timeSpentSeconds, 42);
      expect(s.mistake!.submittedAnswer, '99');

      controller.next();
      expect(state(container).phase, PracticePhase.answering);
      expect(state(container).session!.currentQuestion.id, 'q2');
    });

    test('is a no-op outside retry', () async {
      final container = await makeContainer();
      final controller = await start(container);
      controller.giveUp();
      expect(state(container).phase, PracticePhase.answering);
    });
  });

  group('attempt lifecycle', () {
    test('timing uses the injected clock', () async {
      final container = await makeContainer();
      final controller = await start(container);

      now = now.add(const Duration(seconds: 30));
      controller.submit('4');
      expect(state(container).lastAnswer!.timeSpentSeconds, 30);
    });

    test('advancing resets the attempt for the next question', () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('99');
      controller.requestHint();
      controller.giveUp();
      controller.next();

      final attempt = state(container).attempt!;
      expect(attempt.attempts, 0);
      expect(attempt.hintLevel, 0);
      expect(attempt.lastSubmitted, isNull);

      // The fresh question at full XP — earlier struggles don't leak forward.
      controller.submit('6');
      expect(state(container).lastAnswer!.xpEarned, 10);
    });

    test('hint level is monotonic and capped at 4', () async {
      final container = await makeContainer();
      final controller = await start(container);

      expect(state(container).hintLevel, 0);
      controller.requestHint();
      controller.submit('99'); // → retry; hints still requestable
      controller.requestHint();
      expect(state(container).hintLevel, 2);
      for (var i = 0; i < 10; i++) {
        controller.requestHint();
      }
      expect(state(container).hintLevel, 4);
    });
  });

  group('session completion', () {
    test('the completion bonus lands once on top of per-answer XP', () async {
      final container = await makeContainer();
      final controller = await start(container);

      controller.submit('4'); // +10
      controller.next();
      controller.submit('99');
      controller.giveUp(); // +0
      controller.next(); // completes the session

      final s = state(container);
      expect(s.phase, PracticePhase.complete);
      expect(s.result!.xpEarned, 10 + XpReward.setCompletionBonus);
    });
  });
}
