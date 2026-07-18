import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import 'difficulty_pill.dart';
import 'math_text.dart';

/// The top of the result screen: the detected problem shown large, then the
/// final answer as the single most prominent element on the page (Photomath
/// principle — the mathematics leads, the chrome recedes). Both stay at full
/// size and scroll horizontally when wide, so they never shrink to a squint.
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
        // --- The problem ---
        AppCard(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A slim eyebrow — detection confidence and a rescan escape — kept
              // small so the problem itself is the first thing the eye lands on.
              Row(
                children: [
                  Icon(Icons.check_circle_rounded,
                      size: 14, color: colors.onSuccessContainer),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    context.l10n.resultDetectedConfidence(
                        result.equation.confidencePercent),
                    style: AppTypography.label
                        .copyWith(color: colors.onSuccessContainer),
                  ),
                  const Spacer(),
                  Semantics(
                    button: true,
                    label: context.l10n.resultRescanProblem,
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
                            Text(context.l10n.actionRescan,
                                style: AppTypography.caption
                                    .copyWith(color: colors.textSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // The problem — large, but sized to the content: a short problem
              // gets the full 40px, a long one shrinks to fit rather than
              // scrolling sideways.
              AdaptiveMath(
                result.questionLatex,
                minFontSize: 28,
                maxFontSize: 40,
                style: AppTypography.displaySmall
                    .copyWith(color: colors.textPrimary),
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
        // --- The final answer: the hero of the screen ---
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: colors.successContainer,
            borderRadius: AppRadius.xlRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.l10n.resultFinalAnswer,
                    style: AppTypography.label
                        .copyWith(color: colors.onSuccessContainer),
                  ),
                  const Spacer(),
                  Icon(Icons.verified_rounded,
                      size: 16, color: colors.onSuccessContainer),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Adaptive so it stays readable without scrolling: a short answer
              // fills at 56px, a medium one lands in the 40s, a long one settles
              // near 34px — never a forced 60px, never a sideways scroll.
              AdaptiveMath(
                result.answerLatex,
                minFontSize: 34,
                maxFontSize: 56,
                style: AppTypography.displayLarge.copyWith(
                  color: colors.onSuccessContainer,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _PlayButton(onTap: onPlay),
            ],
          ),
        ),
      ],
    );
  }
}

/// A full-width "play the walkthrough" control — a big, easy target under the
/// answer that reveals the steps one at a time at arm's length.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Emerald content on a raised surface — per-theme legible tone.
    final emeraldLabel =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Semantics(
      button: true,
      label: context.l10n.resultPlayWalkthrough,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          width: double.infinity,
          // md vertical padding keeps the pill at a ≥44px tap target.
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.pillRadius,
            boxShadow: context.elevation.card,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_fill_rounded,
                  size: 22, color: emeraldLabel),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.resultPlayStepByStep,
                style: AppTypography.button
                    .copyWith(color: emeraldLabel, fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
