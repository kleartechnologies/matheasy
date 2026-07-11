import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../result/domain/result_models.dart';
import '../../domain/tutor_models.dart';

/// An inline practice-question card. Shows the question, its difficulty and XP
/// reward, an encouraging line from Matheasy, and a call to action to attempt it.
class TutorPracticeCard extends StatelessWidget {
  const TutorPracticeCard(this.prompt, {super.key, this.onStart});

  final PracticePrompt prompt;

  /// Invoked when the student chooses to attempt the question. The chat screen
  /// decides what happens (full practice sessions arrive in a later stage).
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fitness_center_rounded,
                size: 18,
                color: AppColors.success,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'PRACTICE',
                style: AppTypography.label.copyWith(color: AppColors.success),
              ),
              const Spacer(),
              _DifficultyPill(prompt.difficulty),
              const SizedBox(width: AppSpacing.sm),
              _XpChip(prompt.xpReward),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Semantics(
              label: prompt.questionLatex,
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Math.tex(
                    prompt.questionLatex,
                    mathStyle: MathStyle.text,
                    textStyle: AppTypography.displaySmall.copyWith(
                      color: colors.textPrimary,
                    ),
                    onErrorFallback: (_) => Text(
                      prompt.questionLatex,
                      style: AppTypography.displaySmall.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const MatheasyBrandAvatar(size: 30),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  prompt.encouragement,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Try it',
            icon: Icons.play_arrow_rounded,
            size: AppButtonSize.medium,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _DifficultyPill extends StatelessWidget {
  const _DifficultyPill(this.difficulty);

  final Difficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (difficulty) {
      Difficulty.easy => (colors.successContainer, colors.onSuccessContainer),
      Difficulty.medium => (colors.warningContainer, colors.onWarningContainer),
      Difficulty.hard => (colors.errorContainer, colors.onErrorContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        difficulty.label,
        style: AppTypography.label.copyWith(color: foreground),
      ),
    );
  }
}

class _XpChip extends StatelessWidget {
  const _XpChip(this.xp);

  final int xp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: context.colors.xpContainer,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, size: 13, color: AppColors.xp),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            '$xp XP',
            style: AppTypography.label.copyWith(color: AppColors.amber),
          ),
        ],
      ),
    );
  }
}
