import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/detected_equation.dart';

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
  });

  final DetectedEquation equation;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  /// Opens the math editor pre-filled with the recognized LaTeX so the user can
  /// fix an OCR misread before solving (spec §3 — non-negotiable).
  final VoidCallback onEdit;

  /// Below this recognition confidence we prompt the user to verify rather than
  /// showing a confident check.
  static const double lowConfidenceThreshold = 0.8;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lowConfidence = equation.confidence < lowConfidenceThreshold;
    final accent =
        lowConfidence ? colors.onWarningContainer : colors.onSuccessContainer;

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
          Row(
            children: [
              Icon(
                lowConfidence
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_rounded,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                '${lowConfidence ? 'CHECK THIS' : 'DETECTED'} · '
                '${equation.confidencePercent}%',
                style: AppTypography.label.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _EditableEquation(
            equation: equation,
            highlight: lowConfidence,
            onEdit: onEdit,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            lowConfidence
                ? context.l10n.scanConfirmLowConfidence
                : equation.kind.label,
            style: AppTypography.bodySmall.copyWith(
              color: lowConfidence
                  ? colors.onWarningContainer
                  : colors.textSecondary,
            ),
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
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Math.tex(
                    equation.latex,
                    textStyle: AppTypography.displaySmall
                        .copyWith(color: colors.textPrimary),
                    mathStyle: MathStyle.text,
                    onErrorFallback: (_) => Text(
                      equation.latex,
                      style: AppTypography.displaySmall
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
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
