import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/practice_question.dart';

/// The answer surface for a question — choice tiles for
/// multiple-choice / true-false, or a text field for input / equation.
///
/// Presentation-only: the parent owns the draft answer (via [selectedOption] /
/// [textController]) and grades it. [revealed] switches every control into its
/// locked, correctness-showing state.
class PracticeAnswerArea extends StatelessWidget {
  const PracticeAnswerArea({
    super.key,
    required this.question,
    required this.revealed,
    required this.selectedOption,
    required this.onOptionSelected,
    required this.textController,
    required this.onSubmitInput,
  });

  final PracticeQuestion question;
  final bool revealed;

  /// The chosen option's text (for choice questions).
  final String? selectedOption;
  final ValueChanged<String> onOptionSelected;

  /// The typed answer controller (for input/equation questions).
  final TextEditingController textController;

  /// Called when the on-keyboard "done" action fires.
  final VoidCallback onSubmitInput;

  bool get _isChoice =>
      question.type == PracticeQuestionType.multipleChoice ||
      question.type == PracticeQuestionType.trueFalse;

  @override
  Widget build(BuildContext context) {
    return _isChoice ? _buildOptions(context) : _buildInput(context);
  }

  Widget _buildOptions(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < question.options.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _OptionTile(
            text: question.options[i].text,
            state: _optionState(i),
            onTap: () => onOptionSelected(question.options[i].text),
          ),
        ],
      ],
    );
  }

  _OptionState _optionState(int index) {
    final option = question.options[index];
    if (!revealed) {
      return selectedOption == option.text
          ? _OptionState.selected
          : _OptionState.idle;
    }
    if (option.isCorrect) return _OptionState.correct;
    if (selectedOption == option.text) return _OptionState.wrong;
    return _OptionState.dimmed;
  }

  Widget _buildInput(BuildContext context) {
    final colors = context.colors;
    final wasCorrect = revealed && question.evaluate(textController.text);

    final Color borderColor;
    if (!revealed) {
      borderColor = colors.border;
    } else {
      borderColor = wasCorrect ? AppColors.success : AppColors.error;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: textController,
          enabled: !revealed,
          autofocus: true,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmitInput(),
          keyboardType: question.type == PracticeQuestionType.input
              ? const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                )
              : TextInputType.text,
          inputFormatters: question.type == PracticeQuestionType.input
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9./x=+\- ]'))]
              : null,
          style: AppTypography.headingMedium.copyWith(color: colors.textPrimary),
          cursorColor: AppColors.primary,
          decoration: InputDecoration(
            hintText: 'Type your answer',
            hintStyle: AppTypography.headingMedium.copyWith(
              color: colors.textTertiary,
            ),
            filled: true,
            fillColor: colors.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: AppRadius.mdRadius,
              borderSide: BorderSide(color: borderColor, width: 1.5),
            ),
          ),
        ),
        if (revealed && !wasCorrect) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Correct answer: ${question.correctAnswerText}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.successDeep,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

enum _OptionState { idle, selected, correct, wrong, dimmed }

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String text;
  final _OptionState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (background, borderColor, foreground) = switch (state) {
      _OptionState.idle => (colors.surface, colors.border, colors.textPrimary),
      _OptionState.selected => (
          colors.primaryContainer,
          AppColors.primary,
          colors.onPrimaryContainer,
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
          colors.textTertiary,
        ),
    };

    final trailing = switch (state) {
      _OptionState.correct => Icons.check_circle_rounded,
      _OptionState.wrong => Icons.cancel_rounded,
      _ => null,
    };

    final resultSuffix = switch (state) {
      _OptionState.correct => ', correct answer',
      _OptionState.wrong => ', your answer, incorrect',
      _ => '',
    };

    final interactive = state == _OptionState.idle ||
        state == _OptionState.selected;

    return Semantics(
      button: interactive,
      selected: state == _OptionState.selected,
      label: '$text$resultSuffix',
      child: Pressable(
        onTap: interactive ? onTap : null,
        scale: 0.98,
        borderRadius: AppRadius.mdRadius,
        child: AnimatedContainer(
          duration: AppDurations.medium,
          curve: AppCurves.standard,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.mdRadius,
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    text,
                    style: AppTypography.bodyLarge.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              if (trailing != null)
                Icon(trailing, size: 22, color: borderColor),
            ],
          ),
        ),
      ),
    );
  }
}
