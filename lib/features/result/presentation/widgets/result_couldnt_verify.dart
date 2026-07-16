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
/// This is the deliberate face of the verify-gate architecture (spec §1), and it
/// is NOT an error state: the gate holding is the product's integrity guarantee
/// working as designed. So it carries no error semantics — no red, no amber, no
/// alarm. It leads with what WAS understood (the problem, rendered large and
/// tappable so a misread can be fixed in place), states the miss plainly in the
/// calm `info` family, then offers three real ways forward.
///
/// The honesty stays explicit and unsoftened: no answer is shown or implied,
/// because none passed the check.
class ResultCouldntVerify extends StatelessWidget {
  const ResultCouldntVerify({
    super.key,
    required this.result,
    required this.onRescan,
    required this.onEdit,
    this.onDiscuss,
  });

  final ResultData result;

  /// Rescan from the camera.
  final VoidCallback onRescan;

  /// Open the math editor pre-filled with what we read, to fix a misread — the
  /// primary path (a wrong OCR read is the most common reason a check fails).
  final VoidCallback onEdit;

  /// Open the AI tutor on this problem — the way forward when the read is
  /// already right and the check still failed. Optional: the CTA renders only
  /// where a tutor route is wired.
  final VoidCallback? onDiscuss;

  @override
  Widget build(BuildContext context) {
    final discuss = onDiscuss;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Lead with what I DID understand — it's both the reassurance and the
        // likeliest thing to fix.
        _EditableProblem(latex: result.questionLatex, onEdit: onEdit),
        const SizedBox(height: AppSpacing.md),
        const _VerifyNotice(),
        const SizedBox(height: AppSpacing.xl),

        // Correcting the read is primary — a misread is the likeliest cause.
        PrimaryButton(
          label: 'Edit the problem',
          icon: Icons.edit_rounded,
          onPressed: onEdit,
        ),
        if (discuss != null) ...[
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Work through it with the tutor',
            icon: Icons.forum_rounded,
            onPressed: discuss,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        GhostButton(
          label: 'Rescan',
          icon: Icons.center_focus_strong_rounded,
          expand: true,
          onPressed: onRescan,
        ),
      ],
    );
  }
}

/// The plain statement that nothing passed the check.
///
/// Deliberately the calm `info` family, never `errorContainer`/`warningContainer`
/// — this is considered honesty, not a failure, and the surface has to say so
/// before the words do.
class _VerifyNotice extends StatelessWidget {
  const _VerifyNotice();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: colors.infoContainer,
        borderRadius: AppRadius.xlRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined,
                  size: 18, color: colors.onInfoContainer),
              const SizedBox(width: AppSpacing.xs),
              Text(
                "COULDN'T VERIFY",
                style:
                    AppTypography.label.copyWith(color: colors.onInfoContainer),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'I check every answer by working it back through your problem. This '
            "one didn't pass, so I'm not showing an answer at all — that check "
            'is the whole point. If I misread anything above, correcting it '
            'usually clears this up.',
            style: AppTypography.bodyMedium
                .copyWith(color: colors.onInfoContainer),
          ),
        ],
      ),
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
                style: AppTypography.label.copyWith(color: colors.textMuted),
              ),
              const Spacer(),
              Icon(Icons.edit_rounded, size: 16, color: colors.textMuted),
              const SizedBox(width: 4),
              Text(
                'tap to fix',
                style:
                    AppTypography.caption.copyWith(color: colors.textMuted),
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
