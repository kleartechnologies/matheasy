import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import 'difficulty_pill.dart';
import 'math_text.dart';

/// The top of the result screen: the detected question, then the big answer
/// with a Play Solution button.
class ResultHeader extends StatelessWidget {
  const ResultHeader({
    super.key,
    required this.result,
    required this.onPlay,
    required this.onRescan,
  });

  final ResultData result;
  final VoidCallback onPlay;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 15, color: colors.onSuccessContainer),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'DETECTED · ${result.equation.confidencePercent}%',
                    style: AppTypography.label
                        .copyWith(color: colors.onSuccessContainer),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: 'Rescan the problem',
                    child: GestureDetector(
                      onTap: onRescan,
                      behavior: HitTestBehavior.opaque,
                      // Padded to keep the effective tap target comfortable.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.crop_free_rounded,
                                size: 15, color: colors.textSecondary),
                            const SizedBox(width: AppSpacing.xs),
                            Text('Rescan',
                                style: AppTypography.caption
                                    .copyWith(color: colors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MathText(
                  result.questionLatex,
                  style: AppTypography.displaySmall
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Text(
                    result.type.label,
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  DifficultyPill(result.difficulty),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: colors.successContainer,
            borderRadius: AppRadius.xlRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FINAL ANSWER',
                style: AppTypography.label
                    .copyWith(color: colors.onSuccessContainer),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MathText(
                        result.answerLatex,
                        style: AppTypography.displayMedium
                            .copyWith(color: colors.onSuccessContainer),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _PlayButton(onTap: onPlay),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Play solution walkthrough',
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          // md vertical padding keeps the pill at a ≥44px tap target.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.pillRadius,
            boxShadow: context.elevation.card,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_circle_fill_rounded,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Play',
                style: AppTypography.button
                    .copyWith(color: AppColors.primary, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
