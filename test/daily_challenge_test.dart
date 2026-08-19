// The hardened Daily Challenge system: one challenge per user per local
// calendar day, persisted as a (dayKey, topic, seed) spec whose questions are
// re-DERIVED deterministically (reopen → same challenge), rolled over at the
// first check after midnight (new day → new topic + seed, never yesterday's
// topic), with sticky completion, once-per-day rewards, clock-rollback
// resistance, and cross-device merge.

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/features/practice/application/adaptive_practice_service.dart';
import 'package:matheasy/features/practice/application/daily_challenge_controller.dart';
import 'package:matheasy/features/practice/application/daily_challenge_repository.dart';
import 'package:matheasy/features/practice/application/practice_history_store.dart';
import 'package:matheasy/features/practice/application/practice_progress_controller.dart';
import 'package:matheasy/features/practice/domain/daily_challenge.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_history.dart';
import 'package:matheasy/features/practice/domain/practice_progress.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_session.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/progress/application/achievement_service.dart'
    show clockProvider;
import 'package:matheasy/features/progress/application/trusted_clock.dart';
import 'package:matheasy/features/subscription/application/subscription_controller.dart';
import 'package:matheasy/features/sync/application/sync_merge.dart';
import 'package:matheasy/features/sync/domain/sync_domain.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryHistoryStore implements PracticeHistoryStore {
  PracticeHistory history = PracticeHistory.empty;

  @override
  PracticeHistory load() => history;

  @override
  Future<void> save(PracticeHistory value) async => history = value;
}

AdaptivePracticeService _service({PracticeHistoryStore? history}) =>
    AdaptivePracticeService(
      readProgress: () => PracticeProgress.empty,
      readIsPro: () => false,
      history: history ?? _MemoryHistoryStore(),
      random: Random(7),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const allTopics = PracticeTopic.values;

  group('DailyChallengePlanner.mix', () {
    test('is deterministic, positive, and input-sensitive', () {
      expect(DailyChallengePlanner.mix(123, 456, 7),
          DailyChallengePlanner.mix(123, 456, 7));
      expect(DailyChallengePlanner.mix(123, 456, 7), isNonNegative);
      expect(DailyChallengePlanner.mix(123, 456, 7),
          isNot(DailyChallengePlanner.mix(123, 457, 7)));
      expect(DailyChallengePlanner.mix(123, 456, 7),
          isNot(DailyChallengePlanner.mix(124, 456, 7)));
    });
  });

  group('DailyChallengePlanner.rollover', () {
    test('same (salt, dayKey) always plans the same topic and seed', () {
      final a = DailyChallengePlanner.rollover(DailyChallengeState.empty,
          dayKey: 20000, salt: 42, candidates: allTopics);
      final b = DailyChallengePlanner.rollover(DailyChallengeState.empty,
          dayKey: 20000, salt: 42, candidates: allTopics);
      expect(a.topic, b.topic);
      expect(a.seed, b.seed);
      expect(a.dayKey, 20000);
      expect(a.status, DailyChallengeStatus.notStarted);
    });

    test('a new day never repeats the previous day\'s topic and reseeds', () {
      var state = DailyChallengePlanner.rollover(DailyChallengeState.empty,
          dayKey: 20000, salt: 99, candidates: allTopics);
      for (var day = 20001; day < 20060; day++) {
        final previousTopic = state.topic;
        final previousSeed = state.seed;
        state = DailyChallengePlanner.rollover(state,
            dayKey: day, salt: 99, candidates: allTopics);
        expect(state.topic, isNot(previousTopic),
            reason: 'day $day repeated yesterday\'s topic');
        expect(state.seed, isNot(previousSeed));
      }
    });

    test('even a two-topic pool alternates (avoid window shrinks to fit)', () {
      const pool = [PracticeTopic.algebra, PracticeTopic.fractions];
      var state = DailyChallengePlanner.rollover(DailyChallengeState.empty,
          dayKey: 20000, salt: 5, candidates: pool);
      for (var day = 20001; day < 20010; day++) {
        final previousTopic = state.topic;
        state = DailyChallengePlanner.rollover(state,
            dayKey: day, salt: 5, candidates: pool);
        expect(state.topic, isNot(previousTopic));
      }
    });

    test('rollover archives the outgoing day, newest first, capped', () {
      var state = DailyChallengePlanner.rollover(DailyChallengeState.empty,
          dayKey: 20000, salt: 13, candidates: allTopics);
      for (var day = 20001; day < 20040; day++) {
        state = DailyChallengePlanner.rollover(state,
            dayKey: day, salt: 13, candidates: allTopics);
      }
      expect(state.recent.length, DailyChallengeState.maxRecent);
      expect(state.recent.first.dayKey, 20038); // yesterday, newest first
      expect(state.recent.first.topic, isNotNull);
    });

    test('weights bias the pick toward weak topics', () {
      // With an overwhelming weight, geometry is chosen whenever it is not in
      // the avoid window. Seeded, so this is fully deterministic.
      var picks = 0;
      var eligible = 0;
      var state = DailyChallengeState.empty;
      for (var day = 20000; day < 20030; day++) {
        state = DailyChallengePlanner.rollover(state,
            dayKey: day,
            salt: 17,
            candidates: allTopics,
            weights: const {PracticeTopic.geometry: 1e9});
        final recentTopics =
            state.recent.take(3).map((r) => r.topic).toSet();
        if (!recentTopics.contains(PracticeTopic.geometry)) eligible++;
        if (state.topic == PracticeTopic.geometry) picks++;
      }
      expect(picks, greaterThan(0));
      expect(picks, eligible,
          reason: 'geometry must win whenever the avoid window allows it');
    });
  });

  group('LocalDailyChallengeRepository', () {
    late PreferencesStore prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = PreferencesStore(await SharedPreferences.getInstance());
    });

    test('round-trips the full state', () async {
      final repo = LocalDailyChallengeRepository(prefs);
      final state = DailyChallengePlanner.rollover(
        DailyChallengePlanner.rollover(DailyChallengeState.empty,
            dayKey: 20000, salt: 8, candidates: allTopics),
        dayKey: 20001,
        salt: 8,
        candidates: allTopics,
      ).copyWith(
        status: DailyChallengeStatus.perfect,
        answered: 5,
        correct: 5,
        completedAtMs: 1234567,
      );
      await repo.save(state);
      final loaded = repo.load();
      expect(loaded.salt, state.salt);
      expect(loaded.dayKey, state.dayKey);
      expect(loaded.topic, state.topic);
      expect(loaded.seed, state.seed);
      expect(loaded.questionCount, state.questionCount);
      expect(loaded.status, DailyChallengeStatus.perfect);
      expect(loaded.answered, 5);
      expect(loaded.correct, 5);
      expect(loaded.completedAtMs, 1234567);
      expect(loaded.recent.length, state.recent.length);
      expect(loaded.recent.first.dayKey, state.recent.first.dayKey);
    });

    test('corrupt payload degrades to empty, never throws', () async {
      await prefs.setDailyChallengeJson('{not valid json');
      expect(LocalDailyChallengeRepository(prefs).load().hasChallenge, isFalse);
    });
  });

  group('DailyChallengeController', () {
    late DateTime now;

    Future<ProviderContainer> makeContainer({bool freshPrefs = true}) async {
      if (freshPrefs) SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          isProProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() => now = DateTime(2026, 8, 6, 9)); // a local morning

    test('first build plans today\'s challenge and persists it', () async {
      final container = await makeContainer();
      final state = container.read(dailyChallengeControllerProvider);
      expect(state.hasChallenge, isTrue);
      expect(state.dayKey, PracticeProgress.epochDay(now));
      expect(state.salt, isNot(0));
      expect(state.status, DailyChallengeStatus.notStarted);

      // A second controller over the SAME prefs (an app restart) re-loads the
      // identical spec — it does NOT regenerate.
      final restarted = await makeContainer(freshPrefs: false);
      final again = restarted.read(dailyChallengeControllerProvider);
      expect(again.dayKey, state.dayKey);
      expect(again.topic, state.topic);
      expect(again.seed, state.seed);
      expect(again.salt, state.salt);
    });

    test('midnight rollover: ensureToday plans a NEW challenge', () async {
      final container = await makeContainer();
      final notifier =
          container.read(dailyChallengeControllerProvider.notifier);
      final yesterday = container.read(dailyChallengeControllerProvider);

      now = now.add(const Duration(days: 1)); // past local midnight
      notifier.ensureToday();

      final today = container.read(dailyChallengeControllerProvider);
      expect(today.dayKey, yesterday.dayKey! + 1);
      expect(today.topic, isNot(yesterday.topic));
      expect(today.seed, isNot(yesterday.seed));
      expect(today.status, DailyChallengeStatus.notStarted);
      // The old day is archived with its topic.
      expect(today.recent.first.dayKey, yesterday.dayKey);
      expect(today.recent.first.topic, yesterday.topic);
    });

    test('same-day ensureToday is a no-op (never regenerates)', () async {
      final container = await makeContainer();
      final notifier =
          container.read(dailyChallengeControllerProvider.notifier);
      final before = container.read(dailyChallengeControllerProvider);
      now = now.add(const Duration(hours: 10)); // later the SAME day
      notifier.ensureToday();
      final after = container.read(dailyChallengeControllerProvider);
      expect(identical(before, after), isTrue);
    });

    test('start → answers → completion, and completion is sticky', () async {
      final container = await makeContainer();
      final notifier =
          container.read(dailyChallengeControllerProvider.notifier);
      final request = notifier.todaysRequest();

      notifier.markStarted();
      expect(container.read(dailyChallengeControllerProvider).status,
          DailyChallengeStatus.inProgress);

      notifier.recordAnswer(isCorrect: true);
      notifier.recordAnswer(isCorrect: false);
      var state = container.read(dailyChallengeControllerProvider);
      expect(state.answered, 2);
      expect(state.correct, 1);

      notifier.markCompleted(request: request, correct: 4, total: 5);
      state = container.read(dailyChallengeControllerProvider);
      expect(state.status, DailyChallengeStatus.completed);
      expect(state.answered, state.questionCount);
      expect(state.completedAtMs, now.millisecondsSinceEpoch);

      // Replaying cannot demote or re-open a finished day.
      notifier.markStarted();
      notifier.markCompleted(request: request, correct: 5, total: 5);
      state = container.read(dailyChallengeControllerProvider);
      expect(state.status, DailyChallengeStatus.completed);
      expect(state.correct, 4);
    });

    test('a flawless run is recorded as perfect', () async {
      final container = await makeContainer();
      final notifier =
          container.read(dailyChallengeControllerProvider.notifier);
      final request = notifier.todaysRequest();
      notifier.markStarted();
      notifier.markCompleted(request: request, correct: 5, total: 5);
      expect(container.read(dailyChallengeControllerProvider).status,
          DailyChallengeStatus.perfect);
    });

    test('a stale session (yesterday\'s seed) cannot complete today', () async {
      final container = await makeContainer();
      final notifier =
          container.read(dailyChallengeControllerProvider.notifier);
      final staleRequest = notifier.todaysRequest(); // planned pre-midnight

      now = now.add(const Duration(days: 1));
      notifier.ensureToday();

      notifier.markCompleted(request: staleRequest, correct: 5, total: 5);
      expect(container.read(dailyChallengeControllerProvider).status,
          DailyChallengeStatus.notStarted,
          reason: 'yesterday\'s session must not finish today\'s challenge');
    });

    test('completion state survives an app restart (same prefs)', () async {
      final container = await makeContainer();
      final notifier =
          container.read(dailyChallengeControllerProvider.notifier);
      final request = notifier.todaysRequest();
      notifier.markStarted();
      notifier.markCompleted(request: request, correct: 5, total: 5);
      // The fire-and-forget save resolves within the same event loop turn for
      // the mock prefs; pump the microtask queue.
      await Future<void>.delayed(Duration.zero);

      final restarted = await makeContainer(freshPrefs: false);
      final state = restarted.read(dailyChallengeControllerProvider);
      expect(state.status, DailyChallengeStatus.perfect);
      expect(state.dayKey, PracticeProgress.epochDay(now));
    });
  });

  group('seeded generation (AdaptivePracticeService)', () {
    test('the same seeded request always rebuilds the same questions',
        () async {
      final request = PracticeRequest.dailyChallenge(seed: 987654321);
      final a = await _service().createSession(request);
      final b = await _service().createSession(request);
      expect(a.questions.map((q) => q.prompt).toList(),
          b.questions.map((q) => q.prompt).toList());
      expect(a.questions.map((q) => q.correctAnswerText).toList(),
          b.questions.map((q) => q.correctAnswerText).toList());
    });

    test('different seeds produce different question sets', () async {
      final a = await _service()
          .createSession(PracticeRequest.dailyChallenge(seed: 111));
      final b = await _service()
          .createSession(PracticeRequest.dailyChallenge(seed: 222));
      expect(a.questions.map((q) => q.prompt).toList(),
          isNot(b.questions.map((q) => q.prompt).toList()));
    });

    test('a seeded session never wipes the stored anti-repeat history',
        () async {
      final store = _MemoryHistoryStore();
      // Seed some pre-existing history from ordinary practice.
      final normal = await _service(history: store).createSession(
          const PracticeRequest(topic: PracticeTopic.fractions));
      expect(normal.questions, isNotEmpty);
      await Future<void>.delayed(Duration.zero);
      final before = store.history.recent.length;
      expect(before, greaterThan(0));

      await _service(history: store)
          .createSession(PracticeRequest.dailyChallenge(seed: 42));
      await Future<void>.delayed(Duration.zero);
      expect(store.history.recent.length, greaterThanOrEqualTo(before),
          reason: 'the seeded path must append to history, never replace it '
              'with the empty placeholder it used for generation');
    });
  });

  group('once-per-day rewards (PracticeProgressController)', () {
    late DateTime now;

    Future<ProviderContainer> makeContainer() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => now),
          isProProvider.overrideWithValue(false),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    PracticeSession dailySession(PracticeRequest request) {
      const q = PracticeQuestion(
        id: 'q1',
        topic: PracticeTopic.algebra,
        difficulty: PracticeDifficulty.easy,
        type: PracticeQuestionType.input,
        prompt: 'What is 2 + 2?',
        acceptedAnswers: ['4'],
        explanation: '2 + 2 = 4.',
      );
      return PracticeSession(
        request: request,
        questions: const [q],
        answers: const [
          PracticeAnswer(
              questionId: 'q1', submitted: '4', isCorrect: true, xpEarned: 10),
        ],
      );
    }

    setUp(() => now = DateTime(2026, 8, 6, 9));

    test('replaying the daily challenge the same day earns the bonus once',
        () async {
      final container = await makeContainer();
      final notifier =
          container.read(practiceProgressControllerProvider.notifier);
      final request = container
          .read(dailyChallengeControllerProvider.notifier)
          .todaysRequest();

      notifier.recordSession(dailySession(request), now: now);
      final afterFirst = container.read(practiceProgressControllerProvider);
      expect(afterFirst.dailyChallengesCompleted, 1);
      final xpAfterFirst = afterFirst.totalXp;

      notifier.recordSession(dailySession(request), now: now);
      final afterSecond = container.read(practiceProgressControllerProvider);
      expect(afterSecond.dailyChallengesCompleted, 1,
          reason: 'reopening must never duplicate the daily reward');
      expect(afterSecond.totalXp - xpAfterFirst, lessThan(xpAfterFirst),
          reason: 'the second run must not include the daily bonus again');
    });

    test('winding the clock BACK cannot re-earn the bonus or break the streak',
        () async {
      final container = await makeContainer();
      final notifier =
          container.read(practiceProgressControllerProvider.notifier);
      final request = container
          .read(dailyChallengeControllerProvider.notifier)
          .todaysRequest();

      notifier.recordSession(dailySession(request), now: now);
      final before = container.read(practiceProgressControllerProvider);
      expect(before.dailyChallengesCompleted, 1);
      expect(before.streakCurrent, greaterThanOrEqualTo(1));

      // Roll the clock back a day and replay.
      final rolledBack = now.subtract(const Duration(days: 1));
      notifier.recordSession(dailySession(request), now: rolledBack);
      final after = container.read(practiceProgressControllerProvider);
      expect(after.dailyChallengesCompleted, 1,
          reason: 'a rolled-back clock must not farm the daily bonus');
      expect(after.streakCurrent, greaterThanOrEqualTo(before.streakCurrent),
          reason: 'a rolled-back clock must not destroy the streak');
      expect(after.lastPracticedEpochDay,
          greaterThanOrEqualTo(before.lastPracticedEpochDay!),
          reason: 'day bookkeeping is monotonic');
    });
  });

  group('trusted clock', () {
    Future<ProviderContainer> makeContainer(DateTime deviceNow) async {
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          clockProvider.overrideWithValue(() => deviceNow),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('device time is trusted with no offset or a small one', () async {
      SharedPreferences.setMockInitialValues({});
      final device = DateTime(2026, 8, 6, 9);
      var container = await makeContainer(device);
      expect(container.read(trustedClockProvider)(), device);

      // A modest drift (under the tolerance) is left alone.
      await container
          .read(preferencesStoreProvider)
          .setServerClockOffsetMs(const Duration(minutes: 30).inMilliseconds);
      container = await makeContainer(device);
      expect(container.read(trustedClockProvider)(), device);
    });

    test('an implausible offset (wound clock) is corrected', () async {
      SharedPreferences.setMockInitialValues({});
      final device = DateTime(2026, 8, 9, 9); // wound 3 days ahead
      final container = await makeContainer(device);
      const offset = Duration(days: -3);
      await container
          .read(preferencesStoreProvider)
          .setServerClockOffsetMs(offset.inMilliseconds);
      expect(container.read(trustedClockProvider)(), device.add(offset));
    });
  });

  group('SyncMerge dailyChallenge', () {
    Map<String, dynamic> day(int dayKey,
            {String topic = 'algebra',
            String status = 'notStarted',
            int answered = 0,
            int salt = 7,
            List<Map<String, dynamic>> recent = const []}) =>
        {
          'salt': salt,
          'dayKey': dayKey,
          'topic': topic,
          'seed': 123,
          'questionCount': 5,
          'status': status,
          'answered': answered,
          'correct': 0,
          'recent': recent,
        };

    test('a newer day wins wholesale', () {
      final merged = SyncMerge.merge(
        SyncDomain.dailyChallenge,
        local: day(20001, topic: 'fractions'),
        remote: day(20000, status: 'perfect'),
        remoteNewer: true, // timestamp lies; the dayKey must decide
      );
      expect(merged['dayKey'], 20001);
      expect(merged['topic'], 'fractions');
      expect(merged['status'], 'notStarted');
    });

    test('the same day resolves to the more-finished copy', () {
      final merged = SyncMerge.merge(
        SyncDomain.dailyChallenge,
        local: day(20000, status: 'inProgress', answered: 3),
        remote: day(20000, status: 'perfect', answered: 5),
        remoteNewer: false,
      );
      expect(merged['status'], 'perfect');
      expect(merged['answered'], 5);
    });

    test('recent archives union across devices, one salt survives', () {
      final merged = SyncMerge.merge(
        SyncDomain.dailyChallenge,
        local: day(20002, salt: 11, recent: [
          {'dayKey': 20001, 'topic': 'algebra', 'status': 'completed'},
        ]),
        remote: day(20001, salt: 22, recent: [
          {'dayKey': 20000, 'topic': 'geometry', 'status': 'perfect'},
        ]),
        remoteNewer: false,
      );
      final recent = (merged['recent'] as List).cast<Map<String, dynamic>>();
      expect(recent.map((r) => r['dayKey']), containsAll([20001, 20000]));
      expect(merged['salt'], 11); // the winner's non-zero salt
      expect(merged['dayKey'], 20002);
    });
  });
}
