import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../../shared/mascot/numi_mascot.dart';
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/domain/paywall_trigger.dart';
import '../../tutor/domain/tutor_models.dart';
import '../application/practice_controller.dart';
import '../domain/practice_mistake.dart';
import '../domain/practice_question.dart';
import '../domain/practice_session.dart';
import '../domain/practice_topic.dart';
import 'practice_visual_screen.dart';
import 'widgets/practice_answer_area.dart';
import 'widgets/practice_feedback.dart';
import 'widgets/practice_mistake_actions.dart';
import 'widgets/practice_question_view.dart';
import 'widgets/practice_results_view.dart';
import 'widgets/practice_session_header.dart';

/// The full-screen practice session: build → answer → feedback → next →
/// results. Pushed over the shell with a [PracticeRequest] as the route `extra`.
class PracticeSessionScreen extends ConsumerStatefulWidget {
  const PracticeSessionScreen({super.key, this.request});

  final PracticeRequest? request;

  @override
  ConsumerState<PracticeSessionScreen> createState() =>
      _PracticeSessionScreenState();
}

class _PracticeSessionScreenState
    extends ConsumerState<PracticeSessionScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _started = false;
  String? _selectedOption;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final request = widget.request;
      if (!mounted || _started || request == null) return;
      _started = true;
      unawaited(ref.read(practiceControllerProvider.notifier).start(request));
    });
  }

  @override
  void dispose() {
    _textController
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _resetAnswer() {
    _selectedOption = null;
    _textController.clear();
    if (mounted) setState(() {});
  }

  /// The current answer value, or null when nothing is entered/selected.
  String? _answerFor(PracticeQuestion question) {
    if (question.type == PracticeQuestionType.multipleChoice ||
        question.type == PracticeQuestionType.trueFalse) {
      return _selectedOption;
    }
    final text = _textController.text.trim();
    return text.isEmpty ? null : text;
  }

  void _submit(PracticeQuestion question) {
    final answer = _answerFor(question);
    if (answer == null) return;
    ref.read(practiceControllerProvider.notifier).submit(answer);
  }

  void _next() => ref.read(practiceControllerProvider.notifier).next();

  void _continue() {
    final request = widget.request;
    if (request == null) return;
    _resetAnswer();
    unawaited(ref.read(practiceControllerProvider.notifier).start(request));
  }

  void _exit() {
    ref.read(practiceControllerProvider.notifier).reset();
    Navigator.of(context).maybePop();
  }

  void _openPaywall() {
    ref.read(practiceControllerProvider.notifier).reset();
    context.pushReplacement(
      AppRoutes.paywall,
      extra: PaywallTrigger.practiceLimit,
    );
  }

  /// Opens Numi to explain a wrong answer, seeded with the full mistake context
  /// (question + the learner's answer + the correct answer + topic/difficulty).
  void _askNumiAboutMistake(PracticeMistake mistake) {
    context.push(
      AppRoutes.tutorChat,
      extra: TutorLaunchContext(
        questionLatex: mistake.question.promptLatex,
        answerLatex: mistake.correctAnswer,
        equationType: mistake.difficulty.label,
        topicLabel: mistake.topic.label,
        seedMessage: mistake.numiSeedMessage,
      ),
    );
  }

  /// Launches the Visual Learning walkthrough for a wrong answer. Pro-gated:
  /// free users are routed to the paywall (Visual Learning is a Pro feature).
  void _showVisualForMistake(PracticeMistake mistake) {
    if (!ref.read(isProProvider)) {
      context.push(AppRoutes.paywall, extra: PaywallTrigger.visualLearning);
      return;
    }
    context.push(
      AppRoutes.practiceVisual,
      extra: PracticeVisualArgs(
        latex: mistake.problemLatex,
        answerLatex: mistake.correctAnswer,
        typeHint: _visualTypeHint(mistake.topic),
        topicLabel: mistake.topic.label,
      ),
    );
  }

  /// Maps a practice topic onto the Visual Learning type hint the renderer/mock
  /// keys off (best-effort; the backend treats it as a loose hint).
  String? _visualTypeHint(PracticeTopic topic) => switch (topic) {
        PracticeTopic.algebra => 'linear',
        PracticeTopic.fractions => 'fraction',
        PracticeTopic.trigonometry => 'trigonometry',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    // Reset the local answer whenever the session moves to a new question.
    ref.listen(practiceControllerProvider, (prev, next) {
      if (next.phase == PracticePhase.answering &&
          prev?.session?.currentIndex != next.session?.currentIndex) {
        _resetAnswer();
      }
    });

    final state = ref.watch(practiceControllerProvider);
    final title = widget.request?.displayTitle ?? 'Practice';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Close',
          onPressed: _exit,
        ),
        title: Text(state.isComplete ? 'Results' : title),
      ),
      body: SafeArea(
        top: false,
        child: switch (state.phase) {
          PracticePhase.loading || PracticePhase.idle => const LoadingState(
              message: 'Building your session…',
              showMascot: true,
            ),
          PracticePhase.error => ErrorState(
              message: "We couldn't start that session. Please try again.",
              onRetry: _continue,
            ),
          PracticePhase.complete => PracticeResultsView(
              result: state.result!,
              onContinue: _continue,
              onDone: _exit,
            ),
          PracticePhase.locked => _PracticeLockedView(
              onSeePlans: _openPaywall,
              onNotNow: _exit,
            ),
          PracticePhase.answering ||
          PracticePhase.revealed =>
            _buildActive(state),
        },
      ),
    );
  }

  Widget _buildActive(PracticeSessionState state) {
    final session = state.session!;
    final question = session.currentQuestion;

    return Column(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: AppDurations.medium,
            transitionBuilder: AppTransitions.fadeThrough,
            child: ListView(
              key: ValueKey(session.currentIndex),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.lg,
                AppSpacing.screenH,
                AppSpacing.lg,
              ),
              children: [
                PracticeSessionHeader(session: session),
                const SizedBox(height: AppSpacing.section),
                PracticeQuestionView(question: question),
                const SizedBox(height: AppSpacing.xl),
                PracticeAnswerArea(
                  question: question,
                  revealed: state.isRevealed,
                  selectedOption: _selectedOption,
                  onOptionSelected: (text) =>
                      setState(() => _selectedOption = text),
                  textController: _textController,
                  onSubmitInput: () => _submit(question),
                ),
                if (state.isRevealed) ...[
                  const SizedBox(height: AppSpacing.xl),
                  AppTransitions.slideUp(
                    child: PracticeFeedback(
                      correct: state.lastWasCorrect,
                      explanation: question.explanation,
                      xpEarned: state.lastAnswer?.xpEarned ?? 0,
                      reactionSeed: session.currentIndex,
                    ),
                  ),
                  if (state.mistake case final mistake?) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppTransitions.slideUp(
                      child: PracticeMistakeActions(
                        onAskNumi: () => _askNumiAboutMistake(mistake),
                        onShowVisual: () => _showVisualForMistake(mistake),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        _ActionBar(
          revealed: state.isRevealed,
          isLastQuestion: session.isLastQuestion,
          canSubmit: _answerFor(question) != null,
          onCheck: () => _submit(question),
          onNext: _next,
        ),
      ],
    );
  }
}

/// Shown when a free user has generated all their practice questions. A warm,
/// non-blocking upsell — Numi frames the limit and the primary action opens the
/// paywall; "Maybe later" backs out without pressure.
class _PracticeLockedView extends StatelessWidget {
  const _PracticeLockedView({required this.onSeePlans, required this.onNotNow});

  final VoidCallback onSeePlans;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NumiMascot(expression: NumiExpression.wink, size: 120),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "You're on a roll!",
              textAlign: TextAlign.center,
              style: AppTypography.headingMedium
                  .copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              "You've used all your free practice questions. Go Pro for "
              'unlimited practice tailored to you.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'See Pro plans',
              icon: Icons.workspace_premium_rounded,
              onPressed: onSeePlans,
            ),
            const SizedBox(height: AppSpacing.sm),
            GhostButton(
              label: 'Maybe later',
              expand: true,
              onPressed: onNotNow,
            ),
          ],
        ),
      ),
    );
  }
}

/// The bottom bar: "Check answer" while answering, "Next" / "See results" once
/// revealed. Sits above the keyboard (inside the body, not the Scaffold nav).
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.revealed,
    required this.isLastQuestion,
    required this.canSubmit,
    required this.onCheck,
    required this.onNext,
  });

  final bool revealed;
  final bool isLastQuestion;
  final bool canSubmit;
  final VoidCallback onCheck;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: context.colors.background,
        border: Border(top: BorderSide(color: context.colors.divider)),
      ),
      child: revealed
          ? PrimaryButton(
              label: isLastQuestion ? 'See results' : 'Next',
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: onNext,
            )
          : PrimaryButton(
              label: 'Check answer',
              onPressed: canSubmit ? onCheck : null,
            ),
    );
  }
}
