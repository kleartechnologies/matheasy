import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../subscription/application/subscription_controller.dart';
import '../application/home_controller.dart';
import 'sections/continue_learning.dart';
import 'sections/daily_goal_card.dart';
import 'sections/home_header.dart';
import 'sections/home_progress_card.dart';
import 'sections/home_usage_card.dart';
import 'sections/matheasy_motivation_card.dart';
import 'sections/quick_actions.dart';
import 'sections/recommended_practice.dart';
import 'sections/streak_section.dart';
import 'sections/today_challenge_card.dart';
import 'sections/weak_topics_section.dart';

/// The Matheasy Home dashboard — the app's primary surface.
///
/// Reads mock data from [homeControllerProvider] and composes 10+ sections,
/// each entering with a subtle staggered slide-up. Pull-to-refresh reloads the
/// (mock) data. Never shows an empty dashboard — first-day users get starter
/// content from the section widgets.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeControllerProvider);
    final isPro = ref.watch(isProProvider);

    final sections = <Widget>[
      HomeHeader(userName: data.userName, streak: data.streak),
      DailyGoalCard(goal: data.dailyGoal, isFirstDay: data.isFirstDay),
      const QuickActions(),
      ContinueLearning(courses: data.continueCourses),
      if (data.todayChallenge != null)
        TodayChallengeCard(challenge: data.todayChallenge!),
      StreakSection(streak: data.streak),
      WeakTopicsSection(topics: data.weakTopics),
      RecommendedPractice(items: data.recommendations),
      const HomeProgressCard(),
      MatheasyMotivationCard(message: data.tutorMessage),
      // Subtle upgrade entry point — free users see live usage; Pro users don't
      // see any upsell at all.
      if (!isPro) const HomeUsageCard(),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(homeControllerProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH,
              AppSpacing.lg,
              AppSpacing.screenH,
              AppSpacing.tabClearance,
            ),
            itemCount: sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.section),
            itemBuilder: (context, index) => AppTransitions.slideUp(
              delay: Duration(
                milliseconds: (index * 50).clamp(0, 350),
              ),
              duration: AppDurations.slow,
              child: sections[index],
            ),
          ),
        ),
      ),
    );
  }
}
