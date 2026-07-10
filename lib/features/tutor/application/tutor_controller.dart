import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../subscription/application/usage_controller.dart';
import '../domain/tutor_models.dart';
import 'tutor_service.dart';

part 'tutor_controller.g.dart';

/// Supplies the Tutor home's content: suggested prompts, recent conversations,
/// learning categories and quick actions.
///
/// Entirely mock today (see [TutorHomeContent]); a later stage swaps the source
/// without touching the UI.
@riverpod
TutorHomeData tutorHome(Ref ref) => TutorHomeContent.build();

/// Drives the live chat conversation with Matheasy.
///
/// Holds the running [TutorSession] and orchestrates the send → typing → reply
/// loop through the [TutorService]. Kept alive so the conversation survives
/// navigating away from and back to the chat ("continue conversations"); the
/// screen calls [start] once per open to seed a greeting or auto-send a prompt.
@Riverpod(keepAlive: true)
class TutorChatController extends _$TutorChatController {
  int _seq = 0;

  int _nextId() => _seq++;

  @override
  TutorSession build() => const TutorSession();

  /// Reads the active tutor implementation lazily so provider overrides (real
  /// AI, or a test double) are always honored.
  TutorService get _service => ref.read(tutorServiceProvider);

  /// Called once when the chat screen opens. Seeds a greeting on an empty
  /// session, announces a newly-scanned problem, and/or auto-sends a prompt
  /// carried by [context].
  ///
  /// A *seeded* launch (a tapped suggested prompt or category) always begins a
  /// fresh topic thread — even though this controller is kept alive — so a
  /// starter never appends onto, or duplicates a turn in, an unrelated
  /// persisted conversation. A plain "Ask Matheasy" open (no seed) continues the
  /// existing thread.
  Future<void> start(TutorLaunchContext? context) async {
    unawaited(
        ref.read(analyticsServiceProvider).logEvent(AnalyticsEvent.tutorOpened()));
    final seed = context?.seedMessage?.trim();
    final hasSeed = seed != null && seed.isNotEmpty;

    if (hasSeed && state.messages.isNotEmpty) {
      _seq = 0;
      state = const TutorSession();
    }

    if (state.isEmpty) {
      final messages = <TutorMessage>[];
      if (context != null && context.hasScan) {
        messages.add(
          TutorMessage.system(
            id: _nextId(),
            text: context.hasVisualStep
                ? 'Matheasy can see the visual step you tapped'
                : 'Matheasy can see your scanned problem',
          ),
        );
      }
      final greeting = _service.greeting(context);
      messages.add(_assistantFrom(greeting));
      state = state.copyWith(messages: messages, context: context);
    } else if (context != null &&
        context.hasScan &&
        context != state.context) {
      // Re-entered with a different scanned problem (or a different visual
      // step of the same one) — announce and re-greet.
      final greeting = _service.greeting(context);
      state = state.copyWith(
        context: context,
        messages: [
          ...state.messages,
          TutorMessage.system(
            id: _nextId(),
            text: context.hasVisualStep
                ? 'Now looking at the step you tapped'
                : 'Now looking at your new problem',
          ),
          _assistantFrom(greeting),
        ],
      );
    }

    if (hasSeed) {
      await send(seed);
    }
  }

  /// Sends a free-text [rawText] turn and appends Matheasy's reply. Ignored while
  /// Matheasy is already thinking, so a double-tap can't interleave turns.
  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || state.isTyping) return;

    // Client-side abuse guard (server enforcement is authoritative).
    final limit = ref
        .read(rateLimitServiceProvider)
        .check(RateLimitedAction.tutorMessage);
    if (limit.isLimited) {
      LoggingService.warning('Tutor message rate-limited: ${limit.reason}');
      return;
    }

    // Count every user message against the free-tier AI tutor quota — the single
    // choke point, so seeded prompts and quick replies are all captured.
    ref.read(usageControllerProvider.notifier).recordTutorMessage();
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.tutorMessageSent()));

    state = state.copyWith(
      messages: [
        ...state.messages,
        TutorMessage.user(id: _nextId(), text: text),
      ],
      isTyping: true,
    );

    final response = await _service.reply(
      text,
      history: state.messages,
      context: state.context,
    );

    state = state.copyWith(
      messages: [...state.messages, _assistantFrom(response)],
      isTyping: false,
    );
  }

  /// Sends the message behind a tapped suggestion chip.
  Future<void> sendAction(SuggestionAction action) => send(action.message);

  /// Restores a saved conversation into the live session (from "Recent").
  void loadConversation(TutorConversation conversation) {
    final messages = conversation.messages;
    _seq = messages.isEmpty
        ? 0
        : messages.map((m) => m.id).reduce((a, b) => a > b ? a : b) + 1;
    state = TutorSession(messages: messages);
  }

  /// Clears the thread and re-greets — the chat's "new conversation" action.
  void reset() {
    _seq = 0;
    state = TutorSession(
      messages: [_assistantFrom(_service.greeting(null))],
    );
  }

  TutorMessage _assistantFrom(TutorResponse response) => TutorMessage(
        id: _nextId(),
        role: TutorRole.assistant,
        text: response.text,
        card: response.card,
        suggestions: response.suggestions,
      );
}

/// Builders for the Tutor home's mock content. Isolated here so the UI reads a
/// single [TutorHomeData] object and a later data source can replace this whole
/// class without any widget change.
class TutorHomeContent {
  const TutorHomeContent._();

  static TutorHomeData build() => const TutorHomeData(
        suggestedPrompts: _suggestedPrompts,
        recentConversations: _recentConversations,
        categories: _categories,
        quickActions: _quickActions,
      );

  static const List<TutorPrompt> _suggestedPrompts = [
    TutorPrompt(
      label: 'Explain Algebra',
      icon: Icons.functions_rounded,
      color: AppColors.primary,
      message: 'Can you explain algebra to me?',
    ),
    TutorPrompt(
      label: 'Help Me With Fractions',
      icon: Icons.pie_chart_outline_rounded,
      color: AppColors.secondary,
      message: 'I need help with fractions.',
    ),
    TutorPrompt(
      label: 'Teach Geometry',
      icon: Icons.change_history_rounded,
      color: AppColors.accentAmber,
      message: 'Teach me some geometry.',
    ),
    TutorPrompt(
      label: 'Prepare For Exams',
      icon: Icons.assignment_turned_in_rounded,
      color: AppColors.warning,
      message: 'Help me prepare for my exams.',
    ),
    TutorPrompt(
      label: 'Create A Quiz',
      icon: Icons.quiz_outlined,
      color: AppColors.pink,
      message: 'Create a quiz for me.',
    ),
  ];

  static const List<TutorCategory> _categories = [
    TutorCategory(
      label: 'Algebra',
      icon: Icons.functions_rounded,
      color: AppColors.primary,
      message: 'Can you explain algebra to me?',
    ),
    TutorCategory(
      label: 'Geometry',
      icon: Icons.change_history_rounded,
      color: AppColors.accentAmber,
      message: 'Teach me some geometry.',
    ),
    TutorCategory(
      label: 'Fractions',
      icon: Icons.pie_chart_outline_rounded,
      color: AppColors.secondary,
      message: 'Help me understand fractions.',
    ),
    TutorCategory(
      label: 'Calculus',
      icon: Icons.show_chart_rounded,
      color: AppColors.warning,
      message: 'Can you introduce me to calculus?',
    ),
    TutorCategory(
      label: 'Trigonometry',
      icon: Icons.architecture_rounded,
      color: AppColors.pink,
      message: 'Explain trigonometry to me.',
    ),
    TutorCategory(
      label: 'Word Problems',
      icon: Icons.menu_book_rounded,
      color: AppColors.amber,
      message: 'Help me with word problems.',
    ),
    TutorCategory(
      label: 'Statistics',
      icon: Icons.bar_chart_rounded,
      color: AppColors.accentCoral,
      message: 'Can you teach me statistics?',
    ),
  ];

  static const List<TutorQuickAction> _quickActions = [
    TutorQuickAction(
      label: 'Ask Matheasy',
      icon: Icons.forum_rounded,
      color: AppColors.primary,
      kind: TutorQuickActionKind.askMatheasy,
    ),
    TutorQuickAction(
      label: 'Upload Question',
      icon: Icons.upload_file_rounded,
      color: AppColors.secondary,
      kind: TutorQuickActionKind.uploadQuestion,
    ),
    TutorQuickAction(
      label: 'Practice Topic',
      icon: Icons.fitness_center_rounded,
      color: AppColors.accentAmber,
      kind: TutorQuickActionKind.practiceTopic,
    ),
    TutorQuickAction(
      label: 'Create Quiz',
      icon: Icons.quiz_outlined,
      color: AppColors.warning,
      kind: TutorQuickActionKind.createQuiz,
    ),
  ];

  static const List<TutorConversation> _recentConversations = [
    TutorConversation(
      id: 'c1',
      title: 'Solving Linear Equations',
      preview: 'We subtract 5 because we want x by itself…',
      icon: Icons.calculate_rounded,
      messages: [
        TutorMessage.user(id: 0, text: 'How do I solve 2x + 5 = 13?'),
        TutorMessage(
          id: 1,
          role: TutorRole.assistant,
          text: "Let's isolate x! First subtract 5 from both sides to get "
              '2x = 8, then divide by 2 to find x = 4. 🎉',
          suggestions: [
            SuggestionAction.tellMeWhy,
            SuggestionAction.giveExample,
          ],
        ),
      ],
    ),
    TutorConversation(
      id: 'c2',
      title: 'Understanding Fractions',
      preview: 'Same bottom number first, then add the tops…',
      icon: Icons.pie_chart_outline_rounded,
      messages: [
        TutorMessage.user(id: 0, text: 'How do I add 3/4 + 1/2?'),
        TutorMessage(
          id: 1,
          role: TutorRole.assistant,
          text: 'Make the denominators match! 1/2 is the same as 2/4, so '
              '3/4 + 2/4 = 5/4. Keep the bottom, add the tops. 👍',
          suggestions: [SuggestionAction.explainSimpler],
        ),
      ],
    ),
    TutorConversation(
      id: 'c3',
      title: 'Quadratic Formula Basics',
      preview: 'Plug a, b and c into the formula…',
      icon: Icons.show_chart_rounded,
      messages: [
        TutorMessage.user(id: 0, text: 'What is the quadratic formula?'),
        TutorMessage(
          id: 1,
          role: TutorRole.assistant,
          text: 'The quadratic formula finds x for any ax² + bx + c = 0: '
              'x = (−b ± √(b² − 4ac)) / 2a. It always works, even when '
              'factoring is tricky!',
          suggestions: [
            SuggestionAction.giveExample,
            SuggestionAction.createQuiz,
          ],
        ),
      ],
    ),
  ];
}
