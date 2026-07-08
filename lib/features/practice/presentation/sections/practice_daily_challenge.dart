import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_dashboard.dart';
import '../../domain/practice_session.dart';

/// The daily challenge card — a featured session with a bonus XP reward.
class PracticeDailyChallenge extends StatelessWidget {
  const PracticeDailyChallenge({
    super.key,
    required this.challenge,
    required this.onStart,
  });

  final DailyChallengeView challenge;
  final ValueChanged<PracticeRequest> onStart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: () => onStart(challenge.request),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.xpContainer,
                  borderRadius: AppRadius.smRadius,
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  size: 24,
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      challenge.title,
                      style: AppTypography.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      challenge.subtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _BonusBadge(xp: challenge.bonusXp),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: XPProgressBar(
                  value: challenge.progress,
                  gradient: AppColors.goldGradient,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '${challenge.done} of ${challenge.target}',
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BonusBadge extends StatelessWidget {
  const _BonusBadge({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Bonus $xp XP',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.colors.xpContainer,
          borderRadius: AppRadius.smRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt_rounded, size: 15, color: AppColors.xp),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '+$xp',
              style: AppTypography.label.copyWith(color: AppColors.amber),
            ),
          ],
        ),
      ),
    );
  }
}
