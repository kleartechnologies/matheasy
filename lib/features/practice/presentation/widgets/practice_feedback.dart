import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'practice_chips.dart';

/// The post-answer feedback: a Matheasy reaction, the explanation (once the
/// question resolves), and (when correct) the XP earned. On a wrong answer it
/// names the mistake honestly but warmly — "Your answer / Correct answer" —
/// never a bare "Wrong".
class PracticeFeedback extends StatelessWidget {
  const PracticeFeedback({
    super.key,
    required this.correct,
    required this.explanation,
    required this.xpEarned,
    required this.reactionSeed,
    this.submittedAnswer,
    this.correctAnswer,
  });

  final bool correct;

  /// The "why" — empty while the student can still retry (the explanation
  /// would spoil the learning loop; it appears once the question resolves).
  final String explanation;

  final int xpEarned;

  /// Rotates the Matheasy reaction line so repeats feel fresh.
  final int reactionSeed;

  /// On incorrect: what the student submitted, shown as "Your answer: X".
  final String? submittedAnswer;

  /// On incorrect: the correct answer, shown under the student's.
  final String? correctAnswer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final praise = [
      l10n.practicePraise1,
      l10n.practicePraise2,
      l10n.practicePraise3,
      l10n.practicePraise4,
      l10n.practicePraise5,
    ];
    final encourage = [
      l10n.practiceEncourage1,
      l10n.practiceEncourage2,
      l10n.practiceEncourage3,
      l10n.practiceEncourage4,
    ];
    final headline = correct
        ? praise[reactionSeed % praise.length]
        : encourage[reactionSeed % encourage.length];
    final accent =
        correct ? colors.onSuccessContainer : colors.onWarningContainer;
    final background =
        correct ? colors.successContainer : colors.warningContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.lgRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NumiAvatar(size: 40),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        headline,
                        style: AppTypography.title.copyWith(color: accent),
                      ),
                    ),
                    if (correct && xpEarned > 0) ...[
                      const SizedBox(width: AppSpacing.sm),
                      PracticeXpBadge(xp: xpEarned),
                    ],
                  ],
                ),
                if (!correct && submittedAnswer != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.practiceYourAnswer(submittedAnswer!),
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (correctAnswer case final answer?) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.practiceCorrectAnswer(answer),
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.onSuccessContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
                if (explanation.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    explanation,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
