import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'app_card.dart';

/// A large, centered question surface for practice sessions. Renders the prompt
/// as LaTeX with a plain-text fallback.
class PracticeQuestionCard extends StatelessWidget {
  const PracticeQuestionCard({
    super.key,
    required this.questionTex,
    this.prompt,
  });

  /// The question, as LaTeX (e.g. `3x + 4 = 19`).
  final String questionTex;

  /// Optional instruction above the question (e.g. "Solve for x").
  final String? prompt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxxl,
      ),
      child: Column(
        children: [
          if (prompt != null) ...[
            Text(
              prompt!,
              style: AppTypography.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Math.tex(
            questionTex,
            textStyle: AppTypography.displayMedium
                .copyWith(color: colors.textPrimary),
            mathStyle: MathStyle.text,
            onErrorFallback: (_) => Text(
              questionTex,
              style: AppTypography.displayMedium
                  .copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
