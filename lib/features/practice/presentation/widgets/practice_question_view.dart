import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_question.dart';

/// The question surface: the instruction plus, when present, the equation
/// rendered large. Word-style questions (no LaTeX) show their prompt as the
/// headline.
class PracticeQuestionView extends StatelessWidget {
  const PracticeQuestionView({super.key, required this.question});

  final PracticeQuestion question;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final latex = question.promptLatex;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          if (latex != null) ...[
            Text(
              question.prompt,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Semantics(
              label: '${question.prompt}. '
                  '${question.spokenPrompt ?? question.promptLatex}',
              child: ExcludeSemantics(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Math.tex(
                    latex,
                    mathStyle: MathStyle.text,
                    textStyle: AppTypography.displayMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                    onErrorFallback: (_) => Text(
                      latex,
                      style: AppTypography.displayMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ] else
            Text(
              question.prompt,
              textAlign: TextAlign.center,
              style: AppTypography.headingMedium.copyWith(
                color: colors.textPrimary,
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }
}
