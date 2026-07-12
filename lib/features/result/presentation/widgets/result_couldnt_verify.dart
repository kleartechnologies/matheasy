import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import 'math_text.dart';

/// The honest "couldn't verify" state (spec §1.1 / §9) — shown when `solve()`
/// returns `verified:false` because the answer failed its substitution check.
///
/// This is the deliberate face of the verify-gate architecture: when Matheasy
/// can't stand behind an answer, it shows NONE — never a confident guess. The
/// tone is calm and the failure is framed as the app being careful, NOT the
/// student getting something wrong. It shows what was read (tappable to fix a
/// misread, the likeliest cause) and two real ways forward — edit or rescan —
/// so it's never a dead end.
class ResultCouldntVerify extends StatelessWidget {
  const ResultCouldntVerify({
    super.key,
    required this.result,
    required this.onRescan,
    required this.onEdit,
  });

  final ResultData result;

  /// Rescan from the camera.
  final VoidCallback onRescan;

  /// Open the math editor pre-filled with what we read, to fix a misread — the
  /// primary path (a wrong OCR read is the most common reason a check fails).
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

        // The honest explanation — reassuring, and explicit that this is the
        // app being careful, not the student failing.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: colors.warningContainer,
            borderRadius: AppRadius.xlRadius,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined,
                      size: 18, color: colors.onWarningContainer),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    "COULDN'T VERIFY",
                    style: AppTypography.label
                        .copyWith(color: colors.onWarningContainer),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "I couldn't confirm a reliable answer for this one — so I won't "
                'show a guess. That’s on me, not you: I only show answers I '
                'can check by working them backwards. Fixing a misread usually '
                'sorts it out.',
                style: AppTypography.bodyMedium
                    .copyWith(color: colors.onWarningContainer),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // What we read — tapping it opens the editor to correct a misread.
        _EditableProblem(latex: result.questionLatex, onEdit: onEdit),
        const SizedBox(height: AppSpacing.xl),

        // Two ways forward — editing the read is primary (most likely fix).
        PrimaryButton(
          label: 'Edit the problem',
          icon: Icons.edit_rounded,
          onPressed: onEdit,
        ),
        const SizedBox(height: AppSpacing.md),
        SecondaryButton(
          label: 'Rescan',
          icon: Icons.center_focus_strong_rounded,
          onPressed: onRescan,
        ),
      ],
    );
  }
}

/// The recognized problem, rendered as math, presented as a tappable "tap to
/// fix" card so the student can correct a misread in the editor.
class _EditableProblem extends StatelessWidget {
  const _EditableProblem({required this.latex, required this.onEdit});

  final String latex;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'WHAT I READ',
                style: AppTypography.label.copyWith(color: colors.textTertiary),
              ),
              const Spacer(),
              Icon(Icons.edit_rounded, size: 16, color: colors.textTertiary),
              const SizedBox(width: 4),
              Text(
                'tap to fix',
                style:
                    AppTypography.caption.copyWith(color: colors.textTertiary),
              ),
            ],
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
