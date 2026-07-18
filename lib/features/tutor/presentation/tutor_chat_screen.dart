import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../practice/domain/practice_session.dart';
import '../../practice/domain/practice_topic.dart';
import '../../progress/application/stats_controller.dart';
import '../../subscription/application/usage_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../application/tutor_controller.dart';
import '../domain/tutor_models.dart';
import 'widgets/tutor_chat_input.dart';
import 'widgets/tutor_message_view.dart';

/// The full-screen chat with Matheasy — a modern, premium AI conversation.
///
/// Pushed over the shell. Opens aware of a scanned problem or a tapped prompt
/// when a [launchContext] is supplied. All responses are local mocks today; the
/// screen depends only on [TutorChatController] and the domain models, so a real
/// model swaps in behind the scenes without any change here.
class TutorChatScreen extends ConsumerStatefulWidget {
  const TutorChatScreen({super.key, this.launchContext});

  final TutorLaunchContext? launchContext;

  @override
  ConsumerState<TutorChatScreen> createState() => _TutorChatScreenState();
}

class _TutorChatScreenState extends ConsumerState<TutorChatScreen> {
  final ScrollController _scroll = ScrollController();
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Seed the conversation once the first frame is up (provider mutation is
    // forbidden during build). Guarded so it fires exactly once per open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _started) return;
      _started = true;
      final launch = widget.launchContext;
      final seeded = launch?.seedMessage?.trim().isNotEmpty ?? false;
      // A prompt-seeded open auto-sends a message; if the user is out of free
      // AI tutor messages, replace the chat with the paywall rather than spend one.
      if (seeded && !ref.read(usageSnapshotProvider).canSendTutorMessage) {
        context.pushReplacement(
          AppRoutes.paywall,
          extra: PaywallTrigger.tutorLimit,
        );
        return;
      }
      unawaited(ref.read(tutorChatControllerProvider.notifier).start(launch));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppDurations.medium,
        curve: AppCurves.standard,
      );
    });
  }

  void _recordTutorUse() =>
      ref.read(statsControllerProvider.notifier).recordTutorUsed();

  /// Returns true if an AI tutor message may be sent; otherwise opens the paywall
  /// over the conversation so dismissing it returns the user to the thread.
  bool _ensureTutorQuota() {
    if (ref.read(usageSnapshotProvider).canSendTutorMessage) return true;
    context.push(AppRoutes.paywall, extra: PaywallTrigger.tutorLimit);
    return false;
  }

  void _send(String text) {
    if (!_ensureTutorQuota()) return;
    _recordTutorUse();
    unawaited(ref.read(tutorChatControllerProvider.notifier).send(text));
  }

  void _sendAction(SuggestionAction action) {
    if (!_ensureTutorQuota()) return;
    _recordTutorUse();
    unawaited(ref.read(tutorChatControllerProvider.notifier).sendAction(action));
  }

  void _newChat() {
    ref.read(tutorChatControllerProvider.notifier).reset();
    _toast(context.l10n.tutorNewConversationStarted);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Opens a practice session from a practice card Matheasy offered. Matheasy's
  /// practice prompts are algebra-focused, so we launch an algebra session.
  void _startPractice() {
    context.push(
      AppRoutes.practiceSession,
      extra: const PracticeRequest(topic: PracticeTopic.algebra),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Auto-scroll to the newest message whenever the thread grows or the typing
    // state flips.
    ref.listen(tutorChatControllerProvider, (prev, next) {
      if (prev == null ||
          prev.messages.length != next.messages.length ||
          prev.isTyping != next.isTyping) {
        _scrollToBottom();
      }
    });

    final session = ref.watch(tutorChatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: context.l10n.tutorBack,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const _MatheasyAppBarTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: context.l10n.tutorNewConversation,
            onPressed: _newChat,
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(child: _buildThread(session)),
            TutorChatInput(
              enabled: !session.isTyping,
              onSend: _send,
              onAttach: () => _toast(context.l10n.tutorImageUploadSoon),
              onVoice: () => _toast(context.l10n.tutorVoiceChatSoon),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThread(TutorSession session) {
    if (session.isEmpty) {
      return EmptyState(
        title: context.l10n.tutorEmptyTitle,
        message: context.l10n.tutorEmptyMessage,
      );
    }

    final messages = session.messages;
    final lastAssistant = messages.lastIndexWhere((m) => m.isAssistant);
    final itemCount = messages.length + (session.isTyping ? 1 : 0);

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.lg,
        AppSpacing.screenH,
        AppSpacing.lg,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= messages.length) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Semantics(
              liveRegion: true,
              label: context.l10n.tutorTyping,
              child: const MatheasyTypingIndicator(),
            ),
          );
        }
        final message = messages[index];
        final showSuggestions = !session.isTyping && index == lastAssistant;
        return Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : AppSpacing.lg),
          child: AppTransitions.slideUp(
            child: TutorMessageView(
              message: message,
              showSuggestions: showSuggestions,
              onSuggestion: _sendAction,
              onPracticeStart: _startPractice,
            ),
          ),
        );
      },
    );
  }
}

/// The chat app-bar identity: Matheasy's brand avatar, name and a warm status
/// line.
class _MatheasyAppBarTitle extends StatelessWidget {
  const _MatheasyAppBarTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MatheasyBrandAvatar(size: 34),
        const SizedBox(width: AppSpacing.sm),
        // Flexible + clamped lines so the title never overflows the app bar at
        // large text scales.
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Matheasy',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(color: colors.textPrimary),
              ),
              Text(
                context.l10n.tutorTagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
