import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';

/// The choices offered after a CORRECT answer (V5: never auto-navigate —
/// reflect first): compare your working with Matheasy's method, take on a
/// harder version, or talk it through with Numi. "Next" stays in the action
/// bar below.
class PracticeSuccessActions extends StatelessWidget {
  const PracticeSuccessActions({
    super.key,
    required this.onReviewSolution,
    required this.onAskNumi,
    this.onChallengeMe,
  });

  /// Opens the guided solution in review mode (key idea + memory tip on top).
  final VoidCallback onReviewSolution;

  /// Opens Numi with the solved question as context (alternative methods,
  /// "why does this work?", …).
  final VoidCallback onAskNumi;

  /// Inserts a slightly harder question on the same skill. Hidden when the
  /// engine can't offer one (null).
  final VoidCallback? onChallengeMe;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: l10n.practiceReviewMySolution,
                icon: Icons.fact_check_outlined,
                size: AppButtonSize.medium,
                onPressed: onReviewSolution,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SecondaryButton(
                label: l10n.practiceAskNumi,
                icon: Icons.chat_bubble_outline_rounded,
                size: AppButtonSize.medium,
                onPressed: onAskNumi,
              ),
            ),
          ],
        ),
        if (onChallengeMe != null) ...[
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: l10n.practiceChallengeMe,
            icon: Icons.trending_up_rounded,
            size: AppButtonSize.medium,
            onPressed: onChallengeMe,
          ),
        ],
      ],
    );
  }
}
