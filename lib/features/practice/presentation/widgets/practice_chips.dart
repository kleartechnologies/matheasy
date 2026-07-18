import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/practice_difficulty.dart';
import '../../domain/practice_topic.dart';

/// A small gold XP badge, e.g. "+20 XP".
///
/// Gold is a *surface* here, never ink: the container carries the gold tint and
/// the mark/label sit on it in `onXpContainer`. Raw `AppColors.xp` on the badge
/// would be 1.63:1 gold-on-pale-gold.
class PracticeXpBadge extends StatelessWidget {
  const PracticeXpBadge({super.key, required this.xp, this.showPlus = true});

  final int xp;
  final bool showPlus;

  @override
  Widget build(BuildContext context) {
    final onXp = context.colors.onXpContainer;
    return Semantics(
      label: '${showPlus ? 'Reward ' : ''}$xp XP',
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
            Icon(Icons.bolt_rounded, size: 13, color: onXp),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              '${showPlus ? '+' : ''}$xp XP',
              style: AppTypography.label.copyWith(color: onXp),
            ),
          ],
        ),
      ),
    );
  }
}

/// The topic glyph in its emerald chip — the one topic mark used by the
/// recommended rail, the category grid, the weak-topic rows and "Continue".
/// Topics differ by glyph only; the tint is always the brand emerald.
class PracticeTopicIcon extends StatelessWidget {
  const PracticeTopicIcon({super.key, required this.topic, this.size = 40});

  final PracticeTopic topic;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.smRadius,
      ),
      child: Icon(
        topic.icon,
        // One ratio everywhere, so chips of different sizes still read as a set.
        size: size * 0.55,
        color: colors.onPrimaryContainer,
      ),
    );
  }
}

/// A theme-aware difficulty pill for the practice engine's [PracticeDifficulty].
class PracticeDifficultyPill extends StatelessWidget {
  const PracticeDifficultyPill(this.difficulty, {super.key});

  final PracticeDifficulty difficulty;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (background, foreground) = switch (difficulty) {
      PracticeDifficulty.veryEasy => (
          colors.infoContainer,
          colors.onInfoContainer,
        ),
      PracticeDifficulty.easy => (
          colors.successContainer,
          colors.onSuccessContainer,
        ),
      PracticeDifficulty.medium => (
          colors.warningContainer,
          colors.onWarningContainer,
        ),
      PracticeDifficulty.hard => (
          colors.errorContainer,
          colors.onErrorContainer,
        ),
      PracticeDifficulty.expert => (
          colors.primaryContainer,
          colors.onPrimaryContainer,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        difficulty.label,
        style: AppTypography.label.copyWith(color: foreground),
      ),
    );
  }
}
