import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'app_card.dart';

/// Displays a recognized equation and (optionally) its final answer, rendering
/// LaTeX via `flutter_math_fork`. Falls back to plain text if the LaTeX can't
/// be parsed, so it never crashes on messy OCR input.
class MathSolutionCard extends StatelessWidget {
  const MathSolutionCard({
    super.key,
    required this.equationTex,
    this.label,
    this.caption,
    this.answerTex,
    this.onRescan,
  });

  /// The problem, as a LaTeX string (e.g. `2x + 5 = 13`).
  final String equationTex;

  /// Optional eyebrow, e.g. "DETECTED · 99%".
  final String? label;

  /// Optional supporting caption, e.g. "Linear equation · one unknown".
  final String? caption;

  /// Optional final answer LaTeX (e.g. `x = 4`). When present, a success-tinted
  /// answer strip is shown.
  final String? answerTex;

  final VoidCallback? onRescan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null || onRescan != null)
            Row(
              children: [
                if (label != null)
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 15, color: AppColors.successDeep),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        label!,
                        style: AppTypography.label
                            .copyWith(color: AppColors.successDeep),
                      ),
                    ],
                  ),
                const Spacer(),
                if (onRescan != null)
                  GestureDetector(
                    onTap: onRescan,
                    behavior: HitTestBehavior.opaque,
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
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          _Tex(
            equationTex,
            style: AppTypography.displaySmall
                .copyWith(color: colors.textPrimary),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(caption!,
                style:
                    AppTypography.bodySmall.copyWith(color: colors.textSecondary)),
          ],
          if (answerTex != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: colors.successContainer,
                borderRadius: AppRadius.mdRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('FINAL ANSWER',
                      style: AppTypography.label
                          .copyWith(color: colors.onSuccessContainer)),
                  const SizedBox(height: AppSpacing.xs),
                  _Tex(
                    answerTex!,
                    style: AppTypography.displayMedium
                        .copyWith(color: colors.onSuccessContainer),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// LaTeX renderer with a safe plain-text fallback.
class _Tex extends StatelessWidget {
  const _Tex(this.tex, {required this.style});

  final String tex;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Math.tex(
      tex,
      textStyle: style,
      mathStyle: MathStyle.text,
      onErrorFallback: (_) => Text(tex, style: style),
    );
  }
}
