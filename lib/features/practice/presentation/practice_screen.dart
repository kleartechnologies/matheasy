import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../application/practice_dashboard_controller.dart';
import '../application/practice_difficulty_preference.dart';
import '../domain/practice_session.dart';
import '../domain/practice_skill.dart';
import '../domain/practice_topic.dart';
import 'sections/practice_categories.dart';
import 'sections/practice_continue.dart';
import 'sections/practice_daily_challenge.dart';
import 'sections/practice_header.dart';
import 'sections/practice_recommended_topics.dart';
import 'sections/practice_weak_topics.dart';

/// The Practice dashboard — the tab root. XP + streak header, continue, the
/// daily challenge, recommended + weak topics, and every category. Each path
/// launches a practice session. Reads assembled data from
/// [practiceDashboardProvider], which reacts to persisted progress.
class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key});

  void _start(BuildContext context, PracticeRequest request) =>
      context.push(AppRoutes.practiceSession, extra: request);

  /// Launches a topic. Free users are routed to the paywall for advanced topics
  /// (no free skills); Pro users get an adaptive, weakness-targeted session.
  void _startTopic(BuildContext context, WidgetRef ref, PracticeTopic topic) {
    final isPro = ref.read(isProProvider);
    if (!isPro && !PracticeSkill.topicHasFreeSkills(topic)) {
      context.push(AppRoutes.paywall, extra: PaywallTrigger.adaptivePractice);
      return;
    }
    // Difficulty is the user's explicit choice, held constant for the session;
    // adaptive only reorders topics inside it, never the level.
    final difficulty = ref.read(selectedPracticeDifficultyProvider);
    _start(
      context,
      PracticeRequest(topic: topic, difficulty: difficulty, adaptive: isPro),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(practiceDashboardProvider);

    final sections = <Widget>[
      PracticeHeader(
        xpLevel: data.xpLevel,
        streakCurrent: data.streakCurrent,
        tutorMessage: data.tutorMessage,
      ),
      if (data.continueRequest != null)
        PracticeContinue(
          request: data.continueRequest!,
          onResume: (request) => _start(context, request),
        ),
      PracticeDailyChallenge(
        challenge: data.dailyChallenge,
        onStart: (request) => _start(context, request),
      ),
      PracticeRecommendedTopics(
        topics: data.recommendedTopics,
        onStartTopic: (topic) => _startTopic(context, ref, topic),
      ),
      // Scan-history-driven; absent entirely for a learner with no scans.
      if (data.weakTopics.isNotEmpty)
        PracticeWeakTopics(
          topics: data.weakTopics,
          onStartTopic: (topic) => _startTopic(context, ref, topic),
        ),
      PracticeCategories(
        categories: data.categories,
        onStartTopic: (topic) => _startTopic(context, ref, topic),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.lg,
            AppSpacing.screenH,
            AppSpacing.tabClearance,
          ),
          itemCount: sections.length,
          separatorBuilder: (_, _) =>
              const SizedBox(height: AppSpacing.section),
          itemBuilder: (context, index) => AppTransitions.slideUp(
            delay: Duration(milliseconds: (index * 60).clamp(0, 300)),
            duration: AppDurations.slow,
            child: sections[index],
          ),
        ),
      ),
    );
  }
}
