import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/home_models.dart';

/// A compact daily challenge card — not a hero. Just enough to nudge the streak,
/// and the quietest card on Home: it sits below Scan, Continue and Recommended.
///
/// The XP reward rides in the caption rather than its own gold pill — one gold
/// element per card, so the chip reads as the badge and nothing competes.
class HomeDailyChallengeCard extends StatelessWidget {
  const HomeDailyChallengeCard({super.key, required this.challenge});

  final TodayChallenge challenge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDone = challenge.done >= challenge.target;

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
                  context.l10n.homeTodaysChallenge,
                  style: AppTypography.label.copyWith(color: colors.textMuted),
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
                  isDone
                      ? context.l10n.homeCompletedToday
                      : '${challenge.subtitle} · +${challenge.xpReward} XP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            isDone ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
            // Emerald that holds up as a glyph on this theme's card — primaryDark
            // is 6.83:1 on white but vanishes on a dark one.
            color: isDone
                ? (context.isDark
                    ? AppColors.primaryLight
                    : AppColors.primaryDark)
                : colors.textMuted,
          ),
        ],
      ),
    );
  }
}
