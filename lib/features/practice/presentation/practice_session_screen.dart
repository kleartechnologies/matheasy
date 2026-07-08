import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../application/practice_controller.dart';
import '../domain/practice_question.dart';
import '../domain/practice_session.dart';
import 'widgets/practice_answer_area.dart';
import 'widgets/practice_feedback.dart';
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
