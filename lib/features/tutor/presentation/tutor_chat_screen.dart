import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../../shared/mascot/numi_mascot.dart';
import '../application/tutor_controller.dart';
import '../domain/tutor_models.dart';
import 'widgets/tutor_chat_input.dart';
import 'widgets/tutor_message_view.dart';

/// The full-screen chat with Numi — a modern, premium AI conversation.
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
      unawaited(
        ref
            .read(tutorChatControllerProvider.notifier)
            .start(widget.launchContext),
      );
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

  void _send(String text) =>
      unawaited(ref.read(tutorChatControllerProvider.notifier).send(text));

  void _sendAction(SuggestionAction action) => unawaited(
        ref.read(tutorChatControllerProvider.notifier).sendAction(action),
      );

  void _newChat() {
    ref.read(tutorChatControllerProvider.notifier).reset();
    _toast('Started a new conversation');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const _NumiAppBarTitle(),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'New conversation',
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
              onAttach: () => _toast('Image upload arrives soon.'),
              onVoice: () => _toast('Voice chat arrives soon.'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThread(TutorSession session) {
    if (session.isEmpty) {
      return const Center(
        child: NumiMascot(expression: NumiExpression.thinking),
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
              label: 'Numi is typing',
              child: const NumiTypingIndicator(),
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
              onPracticeStart: () =>
                  _toast('Full practice sessions arrive soon.'),
            ),
          ),
        );
      },
    );
  }
}

/// The chat app-bar identity: Numi's avatar, name and a warm status line.
class _NumiAppBarTitle extends StatelessWidget {
  const _NumiAppBarTitle();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const NumiMascot(size: 34),
        const SizedBox(width: AppSpacing.sm),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Numi',
              style: AppTypography.title.copyWith(color: colors.textPrimary),
            ),
            Text(
              'Your AI math tutor',
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
