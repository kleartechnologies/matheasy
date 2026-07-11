import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/home_models.dart';

/// A compact daily challenge card — not a hero. Just enough to nudge the streak.
class HomeDailyChallengeCard extends StatelessWidget {
  const HomeDailyChallengeCard({super.key, required this.challenge});

  final TodayChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppCard(
      onTap: () => context.go(AppRoutes.practice),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.xpContainer,
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(
              Icons.emoji_events_rounded,
              size: 22,
              color: colors.onXpContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Today's challenge",
                  style: AppTypography.label.copyWith(color: colors.textTertiary),
                ),
                const SizedBox(height: 3),
                Text(
                  challenge.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.title.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '${challenge.done} / ${challenge.target} complete',
                  style: AppTypography.caption.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: colors.xpContainer,
              borderRadius: AppRadius.pillRadius,
            ),
            child: Text(
              '+${challenge.xpReward} XP',
              style: AppTypography.caption.copyWith(
                color: colors.onXpContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
