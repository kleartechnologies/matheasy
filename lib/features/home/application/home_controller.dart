import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/theme/app_colors.dart';
import '../../onboarding/application/onboarding_controller.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../domain/home_models.dart';

part 'home_controller.g.dart';

/// Supplies the Home dashboard's data.
///
/// STAGE 3: entirely mock/in-memory — no backend, no persistence. It lightly
/// personalizes from the onboarding answers (weak topics + daily-goal target)
/// to show the layers connecting; a later stage swaps this for real data.
@riverpod
class HomeController extends _$HomeController {
  @override
  HomeData build() {
    final onboarding = ref.watch(onboardingFlowControllerProvider);
    return HomeMock.returningUser(onboarding);
  }
}

/// Builders for realistic fake Home data.
class HomeMock {
  const HomeMock._();

  static const _weakPalette = [
    AppColors.warning,
    AppColors.pink,
    AppColors.secondary,
  ];

  /// A rich, motivating dashboard for a returning learner, personalized from
  /// the (optional) onboarding answers.
  static HomeData returningUser(OnboardingData onboarding) {
    final target = onboarding.goal?.minutes ?? 15;

    final weakTopics = onboarding.hasTopics
        ? _topicsFrom(onboarding.topics)
        : const [
            WeakTopic(
              label: 'Word Problems',
              icon: Icons.menu_book_rounded,
              accuracy: 54,
              note: 'needs work',
              color: AppColors.warning,
            ),
            WeakTopic(
              label: 'Trigonometry',
              icon: Icons.architecture_rounded,
              accuracy: 61,
              note: 'improving',
              color: AppColors.pink,
            ),
          ];

    return HomeData(
      userName: 'Sarah',
      isFirstDay: false,
      streak: const StreakInfo(current: 12, best: 21),
      dailyGoal: DailyGoalInfo(
        minutesStudied: 8,
        minutesTarget: target,
        lessonsDone: 2,
        lessonsTarget: 3,
      ),
      continueCourses: const [
        CourseProgress(
          title: 'Linear Equations',
          icon: Icons.calculate_rounded,
          color: AppColors.primary,
          completed: 8,
          total: 11,
          estMinutes: 6,
        ),
        CourseProgress(
          title: 'Triangles',
          icon: Icons.change_history_rounded,
          color: AppColors.accentAmber,
          completed: 4,
          total: 10,
          estMinutes: 12,
        ),
        CourseProgress(
          title: 'Fractions',
          icon: Icons.percent_rounded,
          color: AppColors.secondary,
          completed: 9,
          total: 10,
          estMinutes: 3,
        ),
      ],
      todayChallenge: const TodayChallenge(
        title: 'Solve 5 algebra questions',
        subtitle: 'Sharpen your algebra skills',
        done: 2,
        target: 5,
        xpReward: 50,
      ),
      weakTopics: weakTopics,
      recommendations: const [
        PracticeRecommendation(question: r'3x + 4 = 19', difficulty: Difficulty.easy),
        PracticeRecommendation(question: r'5x - 7 = 18', difficulty: Difficulty.medium),
        PracticeRecommendation(question: r'2(x + 3) = 16', difficulty: Difficulty.medium),
      ],
      tutorMessage: "Ready for today's challenge? You're on a 12-day roll! 🔥",
    );
  }

  /// A warm, non-empty first-day dashboard with starter content.
  static HomeData firstDay() {
    return const HomeData(
      userName: 'Sarah',
      isFirstDay: true,
      streak: StreakInfo(current: 0, best: 0),
      dailyGoal: DailyGoalInfo(
        minutesStudied: 0,
        minutesTarget: 10,
        lessonsDone: 0,
        lessonsTarget: 3,
      ),
      continueCourses: [],
      todayChallenge: TodayChallenge(
        title: 'Solve your first problem',
        subtitle: 'Snap a photo or try a quick practice',
        done: 0,
        target: 1,
        xpReward: 20,
      ),
      weakTopics: [],
      recommendations: [
        PracticeRecommendation(question: r'2 + 3 \times 4', difficulty: Difficulty.easy),
        PracticeRecommendation(question: r'x + 7 = 12', difficulty: Difficulty.easy),
      ],
      tutorMessage: "Welcome to Matheasy! Let's solve your first problem together. 🎉",
    );
  }

  static List<WeakTopic> _topicsFrom(Set<MathTopic> topics) {
    const accuracies = [54, 61, 58, 66, 49, 63];
    return [
      for (final (index, topic) in topics.take(3).indexed)
        WeakTopic(
          label: topic.label,
          icon: topic.icon,
          accuracy: accuracies[index % accuracies.length],
          note: accuracies[index % accuracies.length] < 60
              ? 'needs work'
              : 'improving',
          color: _weakPalette[index % _weakPalette.length],
        ),
    ];
  }
}
