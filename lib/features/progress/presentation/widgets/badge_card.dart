import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/achievement_progress.dart';

/// A badge/achievement card. Unlocked badges glow in their accent color; locked
/// ones dim and show progress toward the target.
class AchievementBadgeCard extends StatelessWidget {
  const AchievementBadgeCard({super.key, required this.view, this.onTap});

  final AchievementView view;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final achievement = view.achievement;
    final badge = achievement.badge;
    final unlocked = view.isUnlocked;

    return Semantics(
      button: onTap != null,
      // Own the tap action here — ExcludeSemantics below strips the card's own
      // gesture semantics, so without this the announced button is inert to AT.
      onTap: onTap,
      label: '${badge.name}. ${achievement.description} '
          '${unlocked ? 'Unlocked, reward ${achievement.reward.xp} XP' : 'Locked, '
              '${view.progress.current} of ${view.progress.target}'}',
      child: ExcludeSemantics(
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _BadgeMedallion(
                    emoji: badge.emoji,
                    color: badge.color,
                    unlocked: unlocked,
                  ),
                  const Spacer(),
                  if (unlocked)
                    const Icon(
                      Icons.verified_rounded,
                      size: 18,
                      color: AppColors.success,
                    )
                  else
                    Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: colors.textTertiary,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                badge.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(
                  color: unlocked ? colors.textPrimary : colors.textSecondary,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                achievement.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (unlocked)
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 14, color: AppColors.xp),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      '+${achievement.reward.xp} XP',
                      style: AppTypography.label.copyWith(color: AppColors.amber),
                    ),
                  ],
                )
              else ...[
                XPProgressBar(value: view.progress.fraction, height: 6),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${view.progress.current} / ${view.progress.target}',
                  style: AppTypography.caption.copyWith(
                    color: colors.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The circular emoji medallion — full accent when unlocked, muted when locked.
class _BadgeMedallion extends StatelessWidget {
  const _BadgeMedallion({
    required this.emoji,
    required this.color,
    required this.unlocked,
    this.size = 46,
  });

  final String emoji;
  final Color color;
  final bool unlocked;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: unlocked
            ? color.withValues(alpha: 0.16)
            : colors.surfaceMuted,
        shape: BoxShape.circle,
        border: unlocked
            ? Border.all(color: color.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Opacity(
        opacity: unlocked ? 1 : 0.4,
        child: Text(emoji, style: TextStyle(fontSize: size * 0.46)),
      ),
    );
  }
}

/// The medallion alone, for use outside a card (e.g. the unlock overlay).
class BadgeMedallion extends StatelessWidget {
  const BadgeMedallion({
    super.key,
    required this.emoji,
    required this.color,
    this.size = 46,
    this.unlocked = true,
  });

  final String emoji;
  final Color color;
  final double size;
  final bool unlocked;

  @override
  Widget build(BuildContext context) =>
      _BadgeMedallion(emoji: emoji, color: color, unlocked: unlocked, size: size);
}
