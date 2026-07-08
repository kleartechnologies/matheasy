import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/mascot/numi_mascot.dart';
import '../../domain/achievement.dart';
import 'badge_card.dart';

/// The full-screen celebration shown when an achievement unlocks: a Numi cheer,
/// the badge revealed with a pop, its name/description, the XP reward counting
/// up, and a dismiss.
class AchievementUnlockOverlay extends StatelessWidget {
  const AchievementUnlockOverlay({
    super.key,
    required this.achievement,
    required this.onDismiss,
  });

  final Achievement achievement;
  final VoidCallback onDismiss;

  static const List<String> _cheers = [
    'Amazing work!',
    "You're getting stronger every day!",
    'Incredible — keep it up!',
    'Numi is so proud of you!',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final badge = achievement.badge;
    // Deterministic-but-varied cheer from the achievement identity.
    final cheer = _cheers[achievement.id.index % _cheers.length];

    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        liveRegion: true,
        label: 'Achievement unlocked: ${badge.name}. '
            '${achievement.description} Reward ${achievement.reward.xp} XP.',
        child: Stack(
          children: [
            // Dimmed, tappable backdrop.
            Positioned.fill(
              child: GestureDetector(
                onTap: onDismiss,
                child: AppTransitions.fadeIn(
                  duration: AppDurations.fast,
                  child: ColoredBox(color: colors.scrim),
                ),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: AppTransitions.scaleIn(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: AppRadius.modalRadius,
                        boxShadow: context.elevation.floating,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const _NumiCheer(),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'ACHIEVEMENT UNLOCKED',
                            style: AppTypography.label.copyWith(
                              color: badge.color,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          AppTransitions.scaleIn(
                            delay: AppDurations.fast,
                            from: 0.6,
                            child: BadgeMedallion(
                              emoji: badge.emoji,
                              color: badge.color,
                              size: 96,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            badge.name,
                            textAlign: TextAlign.center,
                            style: AppTypography.headingMedium.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            achievement.description,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _RewardChip(xp: achievement.reward.xp),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            cheer,
                            textAlign: TextAlign.center,
                            style: AppTypography.bodySmall.copyWith(
                              color: badge.color,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          PrimaryButton(
                            label: 'Awesome!',
                            onPressed: onDismiss,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumiCheer extends StatelessWidget {
  const _NumiCheer();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 88,
      child: NumiMascot(expression: NumiExpression.celebrate, size: 88),
    );
  }
}

class _RewardChip extends StatelessWidget {
  const _RewardChip({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.xpContainer,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, size: 18, color: AppColors.xp),
          const SizedBox(width: AppSpacing.xs),
          XpCountUp(
            value: xp,
            prefix: '+',
            suffix: ' XP',
            style: AppTypography.title.copyWith(color: AppColors.amber),
          ),
        ],
      ),
    );
  }
}
