import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/home_controller.dart';
import 'sections/home_continue_card.dart';
import 'sections/home_daily_challenge_card.dart';
import 'sections/home_greeting.dart';
import 'sections/home_hero.dart';
import 'sections/home_recommended_card.dart';

/// The Matheasy Home — deliberately not a dashboard.
///
/// It answers one question the moment it opens: "what should I do next?" A
/// dominant hero (Scan / Type) leads, followed by a single continue card, a
/// single adaptive recommendation and a compact daily challenge. Everything
/// else — streaks, XP, mastery, usage, subscription — lives in Progress and
/// Profile.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeControllerProvider);

    final sections = <Widget>[
      HomeGreeting(userName: data.userName),
      const HomeHero(),
      if (data.continueCourses.isNotEmpty)
        HomeContinueCard(course: data.continueCourses.first),
      if (data.weakTopics.isNotEmpty)
        HomeRecommendedCard(topic: data.weakTopics.first),
      if (data.todayChallenge != null)
        HomeDailyChallengeCard(challenge: data.todayChallenge!),
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
              delay: Duration(milliseconds: (index * 50).clamp(0, 300)),
              duration: AppDurations.slow,
              child: sections[index],
            ),
          ),
        ),
      ),
    );
  }
}
