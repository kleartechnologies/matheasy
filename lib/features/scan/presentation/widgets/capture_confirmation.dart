import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/detected_equation.dart';

/// Bottom confirmation sheet after a capture: shows the recognized problem and
/// offers Retake / Continue.
class CaptureConfirmation extends StatelessWidget {
  const CaptureConfirmation({
    super.key,
    required this.equation,
    required this.onRetake,
    required this.onContinue,
  });

  final DetectedEquation equation;
  final VoidCallback onRetake;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
              Icon(Icons.check_circle_rounded,
                  size: 16, color: colors.onSuccessContainer),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'DETECTED · ${equation.confidencePercent}%',
                style: AppTypography.label
                    .copyWith(color: colors.onSuccessContainer),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Math.tex(
            equation.latex,
            textStyle:
                AppTypography.displaySmall.copyWith(color: colors.textPrimary),
            mathStyle: MathStyle.text,
            onErrorFallback: (_) => Text(
              equation.latex,
              style: AppTypography.displaySmall
                  .copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            equation.kind.label,
            style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Retake',
                  icon: Icons.refresh_rounded,
                  onPressed: onRetake,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: PrimaryButton(
                  label: 'Continue',
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
