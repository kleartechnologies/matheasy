import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/mascot/numi_mascot.dart';
import 'practice_chips.dart';

/// The post-answer feedback: a Numi reaction, the explanation, and (when
/// correct) the XP earned. Warm and encouraging on both outcomes.
class PracticeFeedback extends StatelessWidget {
  const PracticeFeedback({
    super.key,
    required this.correct,
    required this.explanation,
    required this.xpEarned,
    required this.reactionSeed,
  });

  final bool correct;
  final String explanation;
  final int xpEarned;

  /// Rotates the Numi reaction line so repeats feel fresh.
  final int reactionSeed;

  static const List<String> _praise = [
    'Great job!',
    'Nice thinking!',
    'You nailed it!',
    'Brilliant work!',
    "You're on fire! 🔥",
  ];

  static const List<String> _encourage = [
    'Almost there!',
    "Good effort — let's learn from this one.",
    'Not quite, but you can do this!',
    'Close! Take a look at why.',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final headline = correct
        ? _praise[reactionSeed % _praise.length]
        : _encourage[reactionSeed % _encourage.length];
    final accent = correct ? colors.onSuccessContainer : colors.onWarningContainer;
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
          NumiMascot(
            expression:
                correct ? NumiExpression.celebrate : NumiExpression.happy,
            size: 40,
          ),
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
                const SizedBox(height: AppSpacing.xs),
                Text(
                  explanation,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
