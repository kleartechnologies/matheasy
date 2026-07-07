import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/tutor_controller.dart';
import '../domain/tutor_models.dart';
import 'sections/tutor_hero.dart';
import 'sections/tutor_learning_categories.dart';
import 'sections/tutor_quick_actions.dart';
import 'sections/tutor_recent_conversations.dart';
import 'sections/tutor_suggested_prompts.dart';

/// The Tutor home — the landing page for AI learning with Numi.
///
/// A calm, inviting surface: a hero prompt, suggested starters, recent
/// conversations, learning categories and quick actions. Every path opens the
/// chat, optionally seeding it with a prompt. Reads mock content from
/// [tutorHomeProvider]; a later stage swaps the source with no UI change.
class TutorScreen extends ConsumerWidget {
  const TutorScreen({super.key});

  void _openChat(BuildContext context, {TutorLaunchContext? launch}) {
    context.push(AppRoutes.tutorChat, extra: launch);
  }

  void _seed(BuildContext context, String message) =>
      _openChat(context, launch: TutorLaunchContext(seedMessage: message));

  void _openConversation(
    BuildContext context,
    WidgetRef ref,
    TutorConversation conversation,
  ) {
    ref
        .read(tutorChatControllerProvider.notifier)
        .loadConversation(conversation);
    context.push(AppRoutes.tutorChat);
  }

  void _quickAction(
    BuildContext context,
    WidgetRef ref,
    TutorQuickAction action,
  ) {
    switch (action.kind) {
      case TutorQuickActionKind.askNumi:
        _openChat(context);
      case TutorQuickActionKind.uploadQuestion:
        context.push(AppRoutes.scan);
      case TutorQuickActionKind.practiceTopic:
        context.go(AppRoutes.practice);
      case TutorQuickActionKind.createQuiz:
        _seed(context, 'Create a quiz for me.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(tutorHomeProvider);

    final sections = <Widget>[
      TutorHero(onAskNumi: () => _openChat(context)),
      TutorSuggestedPrompts(
        prompts: data.suggestedPrompts,
        onSelected: (prompt) => _seed(context, prompt.message),
      ),
      TutorRecentConversations(
        conversations: data.recentConversations,
        onOpen: (conversation) =>
            _openConversation(context, ref, conversation),
      ),
      TutorLearningCategories(
        categories: data.categories,
        onSelected: (category) => _seed(context, category.message),
      ),
      TutorQuickActions(
        actions: data.quickActions,
        onSelected: (action) => _quickAction(context, ref, action),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.xl,
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
