import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import 'math_text.dart';

/// The "let's work through it together" state (spec §1 golden rule) — shown when
/// `solve()` returns `routeToTutor:true` for a proof / abstract-algebra /
/// real-analysis prompt, a multi-part question, or a system the engine can't
/// prove a complete solution to.
///
/// These problems have no single answer to compute-and-substitute-back, so
/// Matheasy refuses to fake one. Instead of the (misleading) "couldn't verify"
/// error, it honestly names what the problem is ([TutorRouteReason] — a proof
/// must not be confused with a solvable-looking system) and offers the AI tutor
/// as the real way forward. The tone is inviting, not apologetic: this is the
/// right tool for the job, not a failure.
class ResultTutorInvite extends StatelessWidget {
  const ResultTutorInvite({
    super.key,
    required this.result,
    required this.onDiscuss,
    required this.onEdit,
  });

  final ResultData result;

  /// Open the AI tutor, seeded with this problem, to work through it together.
  final VoidCallback onDiscuss;

  /// Open the math editor pre-filled with what we read (in case of a misread).
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        const Center(child: MatheasyBrandAvatar()),
        const SizedBox(height: AppSpacing.xl),

        // The honest framing — this is a reasoning problem, not a computation,
        // and that's a job for the tutor rather than the verify-gate solver.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: AppRadius.xlRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.forum_outlined,
                      size: 18, color: colors.onPrimaryContainer),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    context.l10n.resultLetsReason,
                    style: AppTypography.label
                        .copyWith(color: colors.onPrimaryContainer),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                switch (result.tutorRouteReason) {
                  TutorRouteReason.system =>
                    context.l10n.resultTutorReasonSystem,
                  TutorRouteReason.multiPart =>
                    context.l10n.resultTutorReasonMultiPart,
                  TutorRouteReason.proof =>
                    context.l10n.resultTutorReasonProof,
                },
                style: AppTypography.bodyMedium
                    .copyWith(color: colors.onPrimaryContainer),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _ProblemCard(latex: result.questionLatex),
        const SizedBox(height: AppSpacing.xl),

        // Discussing it with the tutor is the real way forward — make it primary.
        PrimaryButton(
          label: context.l10n.resultWorkThroughTutor,
          icon: Icons.forum_rounded,
          onPressed: onDiscuss,
        ),
        const SizedBox(height: AppSpacing.md),
        SecondaryButton(
          label: context.l10n.resultEditProblem,
          icon: Icons.edit_rounded,
          onPressed: onEdit,
        ),
      ],
    );
  }
}

/// The recognized problem, rendered as math (read-only — the point here is the
/// discussion, not correcting a read).
class _ProblemCard extends StatelessWidget {
  const _ProblemCard({required this.latex});

  final String latex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.resultWhatIRead,
            style: AppTypography.label.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: MathText(
              latex,
              style: AppTypography.displaySmall
                  .copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
