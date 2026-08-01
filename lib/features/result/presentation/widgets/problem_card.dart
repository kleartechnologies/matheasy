import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import 'difficulty_pill.dart';
import 'math_text.dart';

/// V3 · SECTION 1 — the problem, and nothing else.
///
/// The maths leads; the metadata (confidence · category · difficulty) recedes
/// into one quiet caption line beneath it. No answer, no explanation, no CTA —
/// this card answers exactly one question: *what did Matheasy read?*
class ProblemCard extends StatelessWidget {
  const ProblemCard({
    super.key,
    required this.result,
    required this.onRescan,
  });

  final ResultData result;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The problem — the hero of this card. Sized to its content so a short
          // problem gets the full 40px and a long one shrinks rather than
          // scrolling sideways.
          AdaptiveMath(
            result.questionLatex,
            minFontSize: 26,
            maxFontSize: 38,
            style:
                AppTypography.displaySmall.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          // One quiet metadata line: confidence · category · difficulty, with a
          // rescan escape. Deliberately caption-weight — it must never compete
          // with the equation above it.
          Row(
            children: [
              Expanded(
                child: Semantics(
                  container: true,
                  label: '${result.type.label}, ${result.difficulty.label}, '
                      '${context.l10n.resultDetectedConfidence(result.equation.confidencePercent)}',
                  excludeSemantics: true,
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          result.type.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption
                              .copyWith(color: colors.textSecondary),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      DifficultyPill(result.difficulty),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(Icons.check_circle_rounded,
                          size: 12, color: colors.textMuted),
                      const SizedBox(width: AppSpacing.xxs),
                      Flexible(
                        child: Text(
                          '${result.equation.confidencePercent}%',
                          maxLines: 1,
                          style: AppTypography.caption
                              .copyWith(color: colors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                button: true,
                label: context.l10n.resultRescanProblem,
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onRescan,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    // Keeps the effective tap target comfortable without adding
                    // a visible button to the card.
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.sm,
                    ),
                    child: Icon(Icons.crop_free_rounded,
                        size: 18, color: colors.textMuted),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
