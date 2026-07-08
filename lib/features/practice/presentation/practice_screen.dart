import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/practice_dashboard_controller.dart';
import '../domain/practice_session.dart';
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

  void _startTopic(BuildContext context, PracticeTopic topic) =>
      _start(context, PracticeRequest(topic: topic));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(practiceDashboardProvider);

    final sections = <Widget>[
      PracticeHeader(
        xpLevel: data.xpLevel,
        streakCurrent: data.streakCurrent,
        numiMessage: data.numiMessage,
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
        onStartTopic: (topic) => _startTopic(context, topic),
      ),
      PracticeWeakTopics(
        topics: data.weakTopics,
        onStartTopic: (topic) => _startTopic(context, topic),
      ),
      PracticeCategories(
        categories: data.categories,
        onStartTopic: (topic) => _startTopic(context, topic),
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
