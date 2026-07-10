import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/animations/pressable.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../application/visual_solution_controller.dart';
import '../../../domain/result_models.dart';
import '../math_text.dart';
import 'visual_shared_widgets.dart';

/// The locked Visual tab shown to free users: a real Step 1 preview from the
/// already-solved problem (so the value is concrete, not imagined), locked
/// placeholders hinting at the rest, and the Pro pitch with the trial CTA.
/// No AI call is ever made from here.
class VisualTeaser extends ConsumerStatefulWidget {
  const VisualTeaser({
    super.key,
    required this.result,
    required this.onUnlock,
  });

  final ResultData result;
  final VoidCallback onUnlock;

  @override
  ConsumerState<VisualTeaser> createState() => _VisualTeaserState();
}

class _VisualTeaserState extends ConsumerState<VisualTeaser> {
  @override
  void initState() {
    super.initState();
    // Impression analytics live in the tracker (controllers log, widgets
    // don't) — post-frame because providers can't be touched during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(visualTeaserTrackerProvider.notifier)
            .markShown(widget.result.equation);
      }
    });
  }

  /// The first real transformation of the solved problem — the taste of what
  /// Pro unlocks. Falls back to the answer when steps are unavailable.
  SolutionStep? get _previewStep {
    for (final step in widget.result.steps) {
      if (step.resultLatex != widget.result.questionLatex) return step;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final result = widget.result;
    final preview = _previewStep;
    final afterLatex = preview?.resultLatex ?? result.answerLatex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'VISUAL LEARNING',
                    style: AppTypography.label
                        .copyWith(color: colors.textTertiary),
                  ),
                  const Spacer(),
                  const _ProBadge(),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Step 1 preview',
                style: AppTypography.caption
                    .copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.sm),
              // The preview transformation, announced as one sentence.
              Semantics(
                container: true,
                label: '${result.questionLatex} becomes $afterLatex. '
                    'Unlock Pro to watch every step unfold.',
                child: ExcludeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MathText(
                            result.questionLatex,
                            style: AppTypography.headingSmall
                                .copyWith(color: colors.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (preview?.operationLabel != null) ...[
                            VisualOperationChip(
                              label: preview!.operationLabel!,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                          ],
                          const Icon(
                            Icons.arrow_downward_rounded,
                            size: 20,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: MathText(
                            afterLatex,
                            style: AppTypography.headingMedium
                                .copyWith(color: colors.textPrimary),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // The rest of the walkthrough, locked.
              for (var i = 0; i < 2; i++) ...[
                const _LockedStepRow(),
                if (i == 0) const SizedBox(height: AppSpacing.sm),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _UnlockCard(onUnlock: widget.onUnlock),
      ],
    );
  }
}

/// A greyed, locked placeholder row standing in for a hidden step.
class _LockedStepRow extends StatelessWidget {
  const _LockedStepRow();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ExcludeSemantics(
      child: Row(
        children: [
          Icon(Icons.lock_rounded, size: 16, color: colors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: AppRadius.pillRadius,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The premium pitch: navy gradient, gold accents — the app's Pro visual
/// language — with the trial CTA opening the Visual Learning paywall.
class _UnlockCard extends StatelessWidget {
  const _UnlockCard({required this.onUnlock});

  final VoidCallback onUnlock;

  static const List<String> _benefits = [
    'Animated explanations',
    'Interactive visual learning',
    'Visual concept explorer',
    'AI tutor integration',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: const BoxDecoration(
        gradient: AppColors.premiumGradient,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unlock Pro to continue',
            style:
                AppTypography.headingSmall.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Understand math visually — watch every step unfold.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.white.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final benefit in _benefits) ...[
            Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: AppColors.goldLight,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    benefit,
                    style: AppTypography.bodyMedium
                        .copyWith(color: AppColors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            button: true,
            label: 'Start Free Trial',
            child: ExcludeSemantics(
              child: Pressable(
                onTap: onUnlock,
                borderRadius: AppRadius.pillRadius,
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    gradient: AppColors.goldGradient,
                    borderRadius: AppRadius.pillRadius,
                  ),
                  child: Text(
                    'Start Free Trial',
                    style: AppTypography.button
                        .copyWith(color: AppColors.onGold),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              'Unlocks every Pro feature · Cancel anytime',
              style: AppTypography.caption.copyWith(
                color: AppColors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The gold PRO chip — same visual as the profile subscription screen's badge.
class _ProBadge extends StatelessWidget {
  const _ProBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        'PRO',
        style: AppTypography.label.copyWith(color: AppColors.onGold),
      ),
    );
  }
}
