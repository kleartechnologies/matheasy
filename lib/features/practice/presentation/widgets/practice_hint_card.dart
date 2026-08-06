import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../result/application/result_controller.dart';
import '../../../result/domain/result_models.dart' show SolutionStep;
import '../../../result/presentation/widgets/math_text.dart';
import '../../application/practice_solve_bridge.dart';
import '../../domain/practice_hint_fallbacks.dart';
import '../../domain/practice_question.dart';

/// The V5 multi-stage hint ladder, one rung per tap and never more:
///
/// 1. a nudge (authored with the question, or the per-topic fallback)
/// 2. the method pointer
/// 3. the FIRST STEP — lazily solved through the verified pipeline
/// 4. the full guided solution (opens the solution screen)
///
/// Level 0 is just a quiet "Need a hint?" button; nothing is revealed until
/// the student asks, and nothing above the requested level is ever shown.
class PracticeHintCard extends ConsumerWidget {
  const PracticeHintCard({
    super.key,
    required this.question,
    required this.hintLevel,
    required this.onRequestHint,
    required this.onOpenSolution,
  });

  final PracticeQuestion question;

  /// The level the student has requested so far (0–4).
  final int hintLevel;

  /// Escalates one rung (the controller caps at 4).
  final VoidCallback onRequestHint;

  /// Opens the guided solution (rung 4 — the caller marks it viewed).
  final VoidCallback onOpenSolution;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (hintLevel <= 0) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: GhostButton(
          label: context.l10n.practiceNeedHint,
          icon: Icons.lightbulb_outline_rounded,
          onPressed: onRequestHint,
        ),
      );
    }

    final l10n = context.l10n;
    final colors = context.colors;
    final hints = PracticeHintFallbacks.hintsFor(question);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.infoContainer,
        borderRadius: AppRadius.lgRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_rounded,
                  size: 18, color: colors.onInfoContainer),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.practiceHintCounter(hintLevel > 4 ? 4 : hintLevel),
                style: AppTypography.label.copyWith(
                  color: colors.onInfoContainer,
                ),
              ),
            ],
          ),
          for (var level = 1; level <= 2 && level <= hintLevel; level++) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              hints[level - 1],
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ],
          if (hintLevel >= 3) ...[
            const SizedBox(height: AppSpacing.md),
            _FirstStep(question: question),
          ],
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: hintLevel < 3
                ? GhostButton(
                    label: l10n.practiceHintAnother,
                    icon: Icons.add_rounded,
                    onPressed: onRequestHint,
                  )
                : GhostButton(
                    label: l10n.practiceHintSeeSolution,
                    icon: Icons.school_rounded,
                    onPressed: onOpenSolution,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Rung 3 — the verified first step, solved LAZILY the moment it is first
/// requested (this widget only exists at hintLevel ≥ 3, and building it is
/// what triggers the provider). Golden-rule clean: the step shown is the
/// deterministic solver's own first step; when the question can't ride the
/// pipeline, the ladder says so and points at the guided solution instead of
/// inventing anything.
class _FirstStep extends ConsumerWidget {
  const _FirstStep({required this.question});

  final PracticeQuestion question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equation = PracticeSolveBridge.equationFor(question);
    if (equation == null) return const _FirstStepUnavailable();

    final async = ref.watch(resultControllerProvider(equation));
    return async.when(
      loading: () => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            context.l10n.practiceSolutionLoading,
            style: AppTypography.bodySmall.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
      error: (_, _) => const _FirstStepUnavailable(),
      data: (result) {
        if (!result.verified || result.steps.isEmpty) {
          return const _FirstStepUnavailable();
        }
        return _FirstStepView(step: result.steps.first);
      },
    );
  }
}

class _FirstStepView extends StatelessWidget {
  const _FirstStepView({required this.step});

  final SolutionStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.practiceHintFirstStepTitle,
            style: AppTypography.label.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            step.title,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (step.resultLatex.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            MathText(
              step.resultLatex,
              style: AppTypography.headingMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ],
          if (step.detail.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              step.detail,
              style: AppTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FirstStepUnavailable extends StatelessWidget {
  const _FirstStepUnavailable();

  @override
  Widget build(BuildContext context) {
    return Text(
      context.l10n.practiceHintFirstStepUnavailable,
      style: AppTypography.bodySmall.copyWith(
        color: context.colors.textSecondary,
      ),
    );
  }
}
