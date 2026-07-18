import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/services/haptics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';

/// An inline, interactive quiz card. The student taps an option; the card
/// reveals whether it was right, highlights the correct answer and slides open
/// an explanation from Matheasy. Answering is one-shot — once revealed, options
/// lock so the moment of feedback stays clear.
class TutorQuizCard extends StatefulWidget {
  const TutorQuizCard(this.question, {super.key});

  final QuizQuestion question;

  @override
  State<TutorQuizCard> createState() => _TutorQuizCardState();
}

class _TutorQuizCardState extends State<TutorQuizCard> {
  static const List<String> _letters = ['A', 'B', 'C', 'D', 'E', 'F'];

  int? _selected;

  bool get _answered => _selected != null;

  void _choose(int index) {
    if (_answered) return;
    final correct = widget.question.options[index].isCorrect;
    if (correct) {
      HapticsService.success();
    } else {
      HapticsService.warning();
    }
    setState(() => _selected = index);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final question = widget.question;
    final correct = _answered && question.options[_selected!].isCorrect;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.quiz_rounded,
                size: 18,
                color: AppColors.secondary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                context.l10n.tutorQuickQuiz,
                style: AppTypography.label.copyWith(color: AppColors.secondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            question.prompt,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.textSecondary,
            ),
          ),
          if (question.promptLatex != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: question.promptLatex,
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Math.tex(
                    question.promptLatex!,
                    mathStyle: MathStyle.text,
                    textStyle: AppTypography.headingMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                    onErrorFallback: (_) => Text(
                      question.promptLatex!,
                      style: AppTypography.headingMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < question.options.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _OptionTile(
              letter: _letters[i],
              text: question.options[i].text,
              state: _stateFor(i),
              onTap: () => _choose(i),
            ),
          ],
          AnimatedSize(
            duration: AppDurations.medium,
            curve: AppCurves.standard,
            alignment: Alignment.topCenter,
            child: _answered
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.lg),
                    child: AppTransitions.fadeIn(
                      // liveRegion so the result + explanation is announced the
                      // moment it appears, without moving focus.
                      child: Semantics(
                        liveRegion: true,
                        child: _Explanation(
                          correct: correct,
                          text: question.explanation,
                        ),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  _OptionState _stateFor(int index) {
    if (!_answered) return _OptionState.idle;
    final isCorrect = widget.question.options[index].isCorrect;
    if (isCorrect) return _OptionState.correct;
    if (index == _selected) return _OptionState.wrong;
    return _OptionState.dimmed;
  }
}

enum _OptionState { idle, correct, wrong, dimmed }

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.letter,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String letter;
  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (background, borderColor, foreground) = switch (state) {
      _OptionState.idle => (
          colors.surfaceMuted,
          colors.border,
          colors.textPrimary,
        ),
      _OptionState.correct => (
          colors.successContainer,
          AppColors.success,
          colors.onSuccessContainer,
        ),
      _OptionState.wrong => (
          colors.errorContainer,
          AppColors.error,
          colors.onErrorContainer,
        ),
      _OptionState.dimmed => (
          colors.surfaceMuted,
          colors.border,
          colors.textMuted,
        ),
    };

    final trailing = switch (state) {
      _OptionState.correct => Icons.check_circle_rounded,
      _OptionState.wrong => Icons.cancel_rounded,
      _ => null,
    };

    // Once answered, options lock and their result becomes part of the label so
    // a screen reader re-exploring the card hears the outcome, not a "button".
    final resultSuffix = switch (state) {
      _OptionState.correct => ', correct answer',
      _OptionState.wrong => ', your answer, incorrect',
      _ => '',
    };

    return Semantics(
      button: state == _OptionState.idle,
      label: 'Option $letter: $text$resultSuffix',
      child: Pressable(
        onTap: state == _OptionState.idle ? onTap : null,
        scale: 0.98,
        borderRadius: AppRadius.mdRadius,
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: AppCurves.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.mdRadius,
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: foreground.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  letter,
                  style: AppTypography.caption.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  text,
                  style: AppTypography.bodyMedium.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (trailing != null)
                Icon(trailing, size: 20, color: borderColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.correct, required this.text});

  final bool correct;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.mdRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MatheasyBrandAvatar(size: 30),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  correct
                      ? context.l10n.tutorQuizCorrect
                      : context.l10n.tutorQuizNotQuite,
                  style: AppTypography.caption.copyWith(
                    // Theme-aware "on container" tokens: identical to
                    // successDeep/warningDeep in light mode, but legible on the
                    // dark muted surface in dark mode.
                    color: correct
                        ? colors.onSuccessContainer
                        : colors.onWarningContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  text,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
