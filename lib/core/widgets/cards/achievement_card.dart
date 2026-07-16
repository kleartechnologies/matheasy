import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../indicators/xp_progress_bar.dart';
import 'app_card.dart';

/// Badge/achievement tile with locked & unlocked states and optional progress
/// toward unlocking.
class AchievementCard extends StatelessWidget {
  const AchievementCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.unlocked = false,
    this.progress,
    this.accent = AppColors.gold,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool unlocked;

  /// Optional progress (0–1) toward unlocking. Ignored when [unlocked].
  final double? progress;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badgeColor = unlocked ? accent : colors.textMuted;

    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: unlocked
                  ? accent.withValues(alpha: 0.16)
                  : colors.surfaceMuted,
              borderRadius: AppRadius.mdRadius,
            ),
            child: Icon(
              unlocked ? icon : Icons.lock_rounded,
              color: badgeColor,
              size: 26,
            ),
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
                        title,
                        style: AppTypography.title.copyWith(
                          color: unlocked
                              ? colors.textPrimary
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                    if (unlocked)
                      Icon(Icons.verified_rounded, size: 18, color: accent),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  subtitle,
                  style: AppTypography.bodySmall
                      .copyWith(color: colors.textSecondary),
                ),
                if (!unlocked && progress != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  XPProgressBar(value: progress!, height: 6),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
