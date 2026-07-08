// Stage 9 tests — Progress & Achievements.
//
// Covers the achievement evaluation engine, unlock + XP-reward flow, badge/stats
// persistence, analytics (StatsController), the assembled progress overview, and
// the key widgets. Deterministic + offline (fixed clock, mock prefs).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/practice/application/practice_progress_controller.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_session.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/progress/application/achievement_controller.dart';
import 'package:matheasy/features/progress/application/achievement_repository.dart';
import 'package:matheasy/features/progress/application/achievement_service.dart';
import 'package:matheasy/features/progress/application/progress_controller.dart';
import 'package:matheasy/features/progress/application/progress_stats_repository.dart';
import 'package:matheasy/features/progress/application/stats_controller.dart';
import 'package:matheasy/features/progress/domain/achievement.dart';
import 'package:matheasy/features/progress/domain/achievement_catalog.dart';
import 'package:matheasy/features/progress/domain/achievement_progress.dart';
import 'package:matheasy/features/progress/domain/progress_stats.dart';
import 'package:matheasy/features/progress/presentation/progress_screen.dart';
import 'package:matheasy/features/progress/presentation/widgets/achievement_unlock_overlay.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _fixedNow = DateTime(2026, 7, 8);

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      clockProvider.overrideWithValue(() => _fixedNow),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

/// Records a practice session of [questions] correct easy answers.
void _practice(
  ProviderContainer container, {
  int questions = 1,
  bool daily = false,
  PracticeTopic topic = PracticeTopic.algebra,
}) {
  final qs = [
    for (var i = 0; i < questions; i++)
      PracticeQuestion(
        id: '$topic-$i',
        topic: topic,
        difficulty: PracticeDifficulty.easy,
        type: PracticeQuestionType.input,
        prompt: '',
        acceptedAnswers: const ['x'],
        explanation: '',
      ),
  ];
  final answers = [
    for (final q in qs)
      PracticeAnswer(
        questionId: q.id,
        submitted: 'x',
        isCorrect: true,
        xpEarned: 10,
      ),
  ];
  container.read(practiceProgressControllerProvider.notifier).recordSession(
        PracticeSession(
          request: daily
              ? PracticeRequest.dailyChallenge()
              : PracticeRequest(topic: topic),
          questions: qs,
          answers: answers,
        ),
        now: _fixedNow,
      );
}

Set<AchievementId> _unlockedIds(ProviderContainer c) =>
    c.read(achievementControllerProvider).unlocks.keys.toSet();

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('AchievementService', () {
    const service = DefaultAchievementService();

    test('nothing is unlocked or in progress for a fresh learner', () {
      final views = service.evaluate(const AchievementContext(), const {});
      expect(views, hasLength(Achievements.all.length));
      expect(views.every((v) => !v.isUnlocked), isTrue);
      expect(service.pendingUnlocks(const AchievementContext(), const {}),
          isEmpty);
    });

    test('reaching a target makes it pending', () {
      const ctx = AchievementContext(scans: 1, questionsSolved: 10);
      final pending = service.pendingUnlocks(ctx, const {}).map((a) => a.id);
      expect(pending, contains(AchievementId.firstScan));
      expect(pending, contains(AchievementId.solved10));
      expect(pending, isNot(contains(AchievementId.solved50)));
    });

    test('progress fraction reflects partial completion', () {
      const ctx = AchievementContext(questionsSolved: 5);
      final view = service
          .evaluate(ctx, const {})
          .firstWhere((v) => v.achievement.id == AchievementId.solved10);
      expect(view.progress.current, 5);
      expect(view.progress.target, 10);
      expect(view.progress.fraction, 0.5);
      expect(view.status, AchievementStatus.inProgress);
    });

    test('already-unlocked achievements are not re-pending', () {
      const ctx = AchievementContext(scans: 1);
      final unlocks = {AchievementId.firstScan: _fixedNow};
      expect(service.pendingUnlocks(ctx, unlocks), isEmpty);
    });
  });

  group('AchievementController — unlock + rewards', () {
    test('a scan unlocks First Scan and awards its XP', () async {
      final container = await _container();
      container.listen(achievementControllerProvider, (_, _) {});
      await _pump();

      container.read(statsControllerProvider.notifier).recordScan();
      await _pump();

      final state = container.read(achievementControllerProvider);
      expect(state.unlocks.containsKey(AchievementId.firstScan), isTrue);
      expect(state.pending.map((a) => a.id), contains(AchievementId.firstScan));
      // First Scan rewards 20 XP into the practice XP ledger.
      expect(container.read(practiceProgressControllerProvider).totalXp, 20);
    });

    test('a 10-question session unlocks the starter + volume badges', () async {
      final container = await _container();
      container.listen(achievementControllerProvider, (_, _) {});
      await _pump();

      _practice(container, questions: 10);
      await _pump();

      final unlocked = _unlockedIds(container);
      expect(
        unlocked,
        containsAll([
          AchievementId.firstPractice,
          AchievementId.firstCorrect,
          AchievementId.solved10,
        ]),
      );
      // 100 session XP + (25 + 15 + 30) achievement bonuses.
      expect(container.read(practiceProgressControllerProvider).totalXp, 170);
    });

    test('daily challenge + 3 topics unlock their achievements', () async {
      final container = await _container();
      container.listen(achievementControllerProvider, (_, _) {});
      await _pump();

      _practice(container, daily: true);
      _practice(container, topic: PracticeTopic.fractions);
      _practice(container, topic: PracticeTopic.geometry);
      await _pump();

      final unlocked = _unlockedIds(container);
      expect(unlocked, contains(AchievementId.dailyChallenge));
      expect(unlocked, contains(AchievementId.explore3Topics));
    });

    test('dismissCelebration advances the queue', () async {
      final container = await _container();
      container.listen(achievementControllerProvider, (_, _) {});
      await _pump();
      container.read(statsControllerProvider.notifier).recordScan();
      await _pump();

      final before = container.read(achievementControllerProvider).pending.length;
      expect(before, greaterThan(0));
      container.read(achievementControllerProvider.notifier).dismissCelebration();
      expect(
        container.read(achievementControllerProvider).pending.length,
        before - 1,
      );
    });

    test('an unlock is not re-awarded on re-evaluation', () async {
      final container = await _container();
      container.listen(achievementControllerProvider, (_, _) {});
      await _pump();

      container.read(statsControllerProvider.notifier).recordScan();
      await _pump();
      container.read(statsControllerProvider.notifier).recordScan();
      await _pump();

      // XP for First Scan (20) is granted once, even after a second scan.
      expect(container.read(practiceProgressControllerProvider).totalXp, 20);
    });
  });

  group('StatsController', () {
    test('records scans, learning days and activity', () async {
      final container = await _container();
      final stats = container.read(statsControllerProvider.notifier);

      stats.recordScan();
      final state = container.read(statsControllerProvider);
      expect(state.scans, 1);
      expect(state.learningDayCount, 1);
      expect(state.recentActivity.first.type, LearningActivityType.scan);
    });

    test('tutor use logs only its first activity entry', () async {
      final container = await _container();
      final stats = container.read(statsControllerProvider.notifier);

      stats.recordTutorUsed();
      stats.recordTutorUsed();
      final state = container.read(statsControllerProvider);
      expect(state.tutorUses, 2);
      expect(
        state.recentActivity
            .where((a) => a.type == LearningActivityType.tutor)
            .length,
        1,
      );
    });
  });

  group('Persistence', () {
    test('achievement repository round-trips unlocks', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalAchievementRepository(PreferencesStore(prefs));

      final unlocks = {
        AchievementId.firstScan: DateTime(2026),
        AchievementId.streak7: DateTime(2026, 7, 8),
      };
      await repo.save(unlocks);
      final loaded = repo.load();
      expect(loaded.keys.toSet(), unlocks.keys.toSet());
      expect(loaded[AchievementId.streak7], DateTime(2026, 7, 8));
    });

    test('stats repository round-trips analytics + activity', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final repo = LocalProgressStatsRepository(PreferencesStore(prefs));

      const stats = ProgressStats(
        scans: 3,
        tutorUses: 2,
        learningDays: {20000, 20001},
        recentActivity: [
          LearningActivity(
            type: LearningActivityType.achievement,
            title: 'Unlocked On Fire',
            subtitle: '3 day streak',
            epochMillis: 1000,
            emoji: '🔥',
          ),
        ],
      );
      await repo.save(stats);
      final loaded = repo.load();
      expect(loaded.scans, 3);
      expect(loaded.tutorUses, 2);
      expect(loaded.learningDays, {20000, 20001});
      expect(loaded.recentActivity.single.emoji, '🔥');
    });

    test('corrupt payloads fall back to empty', () async {
      SharedPreferences.setMockInitialValues({
        'progress.achievements': 'nope',
        'progress.stats': '{bad',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = PreferencesStore(prefs);
      expect(LocalAchievementRepository(store).load(), isEmpty);
      expect(LocalProgressStatsRepository(store).load().scans, 0);
    });
  });

  group('ProgressController overview', () {
    test('aggregates learning stats from practice + analytics', () async {
      final container = await _container();
      container.listen(achievementControllerProvider, (_, _) {});
      await _pump();

      _practice(container, questions: 4);
      container.read(statsControllerProvider.notifier).recordScan();
      await _pump();

      final overview = container.read(progressControllerProvider);
      expect(overview.questionsSolved, 4);
      expect(overview.correctAnswers, 4);
      expect(overview.sessionsCompleted, 1);
      expect(overview.topicsPracticed, 1);
      expect(overview.achievementsTotal, Achievements.all.length);
      expect(overview.achievementsUnlocked, greaterThan(0));
      expect(overview.mastery, hasLength(PracticeTopic.values.length));
    });
  });

  group('Widgets', () {
    testWidgets('unlock overlay shows the badge, reward and dismiss',
        (tester) async {
      final achievement = Achievements.byId(AchievementId.streak7);
      var dismissed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: AchievementUnlockOverlay(
              achievement: achievement,
              onDismiss: () => dismissed = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Week Warrior'), findsOneWidget);
      expect(find.text('Awesome!'), findsOneWidget);

      await tester.tap(find.text('Awesome!'));
      expect(dismissed, isTrue);
    });

    testWidgets('progress screen renders the header and overview', (tester) async {
      final container = await _container();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ProgressScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Learning overview'), findsOneWidget);
    });
  });
}
