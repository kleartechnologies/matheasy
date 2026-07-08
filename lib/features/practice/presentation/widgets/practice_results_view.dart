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
import '../../domain/practice_result.dart';

/// The session-complete screen: accuracy, XP earned, mastery progress and a
/// Numi summary, with actions to keep practicing or finish.
class PracticeResultsView extends StatelessWidget {
  const PracticeResultsView({
    super.key,
    required this.result,
    required this.onContinue,
    required this.onDone,
  });

  final PracticeResult result;
  final VoidCallback onContinue;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.xl,
        AppSpacing.screenH,
        AppSpacing.xl,
      ),
      children: [
        AppTransitions.scaleIn(
          child: Center(
            child: NumiMascot(
              expression: result.isPerfect
                  ? NumiExpression.celebrate
                  : NumiExpression.happy,
              size: 104,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          result.isPerfect ? 'Perfect! 🎉' : 'Session complete!',
          textAlign: TextAlign.center,
          style: AppTypography.displaySmall.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          _summary(result),
          textAlign: TextAlign.center,
          style: AppTypography.bodyLarge.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppTransitions.slideUp(
          delay: AppDurations.fast,
          child: _StatsRow(result: result),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTransitions.slideUp(
          delay: AppDurations.medium,
          child: _MasteryCard(result: result),
        ),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Keep practicing',
          icon: Icons.replay_rounded,
          onPressed: onContinue,
        ),
        const SizedBox(height: AppSpacing.md),
        GhostButton(
          label: 'Done',
          expand: true,
          onPressed: onDone,
        ),
      ],
    );
  }

  String _summary(PracticeResult result) {
    if (result.isPerfect) {
      return 'A flawless run on ${result.topic.label}. Numi is impressed!';
    }
    if (result.accuracy >= 0.6) {
      return "Solid work on ${result.topic.label} — you're getting stronger!";
    }
    return "Every attempt builds mastery. Let's keep going on "
        '${result.topic.label}!';
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.result});

  final PracticeResult result;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.check_circle_rounded,
            color: AppColors.success,
            value: '${result.correct}/${result.total}',
            label: 'Correct',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatTile(
            icon: Icons.percent_rounded,
            color: AppColors.primary,
            value: '${result.accuracyPercent}%',
            label: 'Accuracy',
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatTile(
            icon: Icons.bolt_rounded,
            color: AppColors.xp,
            value: '+${result.xpEarned}',
            label: 'XP earned',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: AppSpacing.sm),
              Text(
                value,
                style: AppTypography.headingSmall.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MasteryCard extends StatelessWidget {
  const _MasteryCard({required this.result});

  final PracticeResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Row(
        children: [
          Semantics(
            container: true,
            label: '${result.topic.label} mastery: ${result.masteryAfter.label}'
                ', ${(result.masteryProgress * 100).round()}% to next level',
            child: ProgressRing(
              value: result.masteryProgress,
              progressColor: result.topic.color,
              child: ExcludeSemantics(
                child: Text(
                  result.masteryAfter.label.substring(0, 1),
                  style: AppTypography.headingSmall.copyWith(
                    color: result.topic.color,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${result.topic.label} mastery',
                  style: AppTypography.title.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  result.masteryAfter.label,
                  style: AppTypography.bodyMedium.copyWith(
                    color: result.topic.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (result.leveledUp) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xxs,
                    ),
                    decoration: BoxDecoration(
                      color: colors.successContainer,
                      borderRadius: AppRadius.pillRadius,
                    ),
                    child: Text(
                      'Level up! ${result.masteryBefore.label} → '
                      '${result.masteryAfter.label}',
                      style: AppTypography.label.copyWith(
                        color: colors.onSuccessContainer,
                      ),
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
