import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
// The recognized-problem renderer is shared with the result screen (as the
// history tile already shares its math widgets) — one place decides how a read
// is shown to a student, so the scan sheet and the result card can't drift.
import '../../../result/presentation/widgets/problem_statement.dart';
import '../../domain/detected_equation.dart';
import '../equation_kind_l10n.dart';
import 'confidence_badge.dart';

/// Bottom confirmation sheet after a capture: shows the recognized problem —
/// rendered as real math and TAPPABLE to edit (spec §3 non-negotiable) — a
/// confidence indicator that prompts a check when low, and Retake / Solve.
class CaptureConfirmation extends StatelessWidget {
  const CaptureConfirmation({
    super.key,
    required this.equation,
    required this.onRetake,
    required this.onContinue,
    required this.onEdit,
    this.onAdjust,
  });

  final DetectedEquation equation;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  /// Opens the math editor pre-filled with the recognized LaTeX so the user can
  /// fix an OCR misread before solving (spec §3 — non-negotiable).
  final VoidCallback onEdit;

  /// Re-opens the crop screen on the original photo, when the capture was
  /// auto-cropped and the framing needs overruling. Null when there is no
  /// original to go back to — a typed problem, or a re-read of a manual crop.
  final VoidCallback? onAdjust;

  /// Below this recognition confidence we prompt the user to verify rather than
  /// showing a confident check.
  static const double lowConfidenceThreshold =
      DetectedEquation.lowConfidenceThreshold;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lowConfidence = equation.confidence < lowConfidenceThreshold;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.sheetRadius,
      ),
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl,
        AppSpacing.xl + context.viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // How the read went, as a state the student can act on — a percentage
          // is precision this number doesn't have.
          ConfidenceBadge(
            equation.readConfidence,
            prominent: true,
            style: AppTypography.label,
          ),
          const SizedBox(height: AppSpacing.md),
          _EditableEquation(
            equation: equation,
            highlight: lowConfidence,
            onEdit: onEdit,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  lowConfidence
                      ? context.l10n.scanConfirmLowConfidence
                      : equation.kind.labelOf(context),
                  style: AppTypography.bodySmall.copyWith(
                    color: lowConfidence
                        ? colors.onWarningContainer
                        : colors.textSecondary,
                  ),
                ),
              ),
              // The way out of a bad automatic crop. Quiet by design: it sits
              // beside the read rather than beneath it, because the common case
              // is that the crop was right and the user should be looking at the
              // maths, not at a framing control.
              if (onAdjust != null) ...[
                const SizedBox(width: AppSpacing.sm),
                _AdjustButton(onTap: onAdjust!),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: context.l10n.scanRetake,
                  icon: Icons.refresh_rounded,
                  onPressed: onRetake,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: PrimaryButton(
                  label: context.l10n.scanSolve,
                  trailingIcon: Icons.arrow_forward_rounded,
                  onPressed: onContinue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Adjust" — re-frame the photo when the automatic crop cut the wrong thing.
///
/// Takes the theme's adaptive emerald ink rather than `AppColors.primary`: the
/// identity emerald is brand art, and as a label on this sheet it would fail
/// contrast in light mode and disappear in dark.
class _AdjustButton extends StatelessWidget {
  const _AdjustButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.scanAdjustCrop,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smRadius,
        child: Padding(
          // Keeps the 48px hit target the label alone wouldn't give.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.crop_rounded, size: 16, color: colors.onPrimaryContainer),
              const SizedBox(width: 4),
              Text(
                context.l10n.scanAdjustCrop,
                style: AppTypography.label.copyWith(color: colors.onPrimaryContainer),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The recognized equation rendered as real math and TAPPABLE to edit — the
/// heart of §3. Tapping opens the math editor pre-filled with this LaTeX; the
/// edit pencil + framed container signal that it's fixable.
class _EditableEquation extends StatelessWidget {
  const _EditableEquation({
    required this.equation,
    required this.highlight,
    required this.onEdit,
  });

  final DetectedEquation equation;
  final bool highlight;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.scanEditEquation,
      excludeSemantics: true,
      child: InkWell(
        onTap: onEdit,
        borderRadius: AppRadius.mdRadius,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdRadius,
            border: Border.all(
              color: highlight ? colors.onWarningContainer : colors.border,
              width: highlight ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              // Typeset, never source: this is the student's one chance to
              // check the read against the page in front of them.
              Expanded(
                child: ProblemStatement(
                  latex: equation.latex,
                  minFontSize: 20,
                  maxFontSize: 28,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.edit_rounded, size: 18, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
