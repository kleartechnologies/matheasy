import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_result.dart';

/// The session-complete screen: accuracy, XP earned, mastery progress and a
/// Matheasy summary, with actions to keep practicing or finish.
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
          child: const Center(
            child: MatheasyBrandAvatar(size: 104),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          result.isPerfect
              ? context.l10n.practicePerfect
              : context.l10n.practiceSessionComplete,
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
          label: context.l10n.practiceKeepPracticing,
          icon: Icons.replay_rounded,
          onPressed: onContinue,
        ),
        const SizedBox(height: AppSpacing.md),
        GhostButton(
          label: context.l10n.actionDone,
          expand: true,
          onPressed: onDone,
        ),
      ],
    );
  }

  String _summary(PracticeResult result) {
    if (result.isPerfect) {
      return 'A flawless run on ${result.topic.label}. Matheasy is impressed!';
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
    final colors = context.colors;
    // Three semantic containers, one shape — no per-stat accent hues. XP keeps
    // its gold, but as a tinted chip with ink on it rather than gold-on-card
    // (1.63:1).
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.check_circle_rounded,
            tint: colors.successContainer,
            onTint: colors.onSuccessContainer,
            value: '${result.correct}/${result.total}',
            label: context.l10n.practiceStatCorrect,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatTile(
            icon: Icons.percent_rounded,
            tint: colors.infoContainer,
            onTint: colors.onInfoContainer,
            value: '${result.accuracyPercent}%',
            label: context.l10n.practiceStatAccuracy,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatTile(
            icon: Icons.bolt_rounded,
            tint: colors.xpContainer,
            onTint: colors.onXpContainer,
            value: '+${result.xpEarned}',
            label: context.l10n.practiceStatXpEarned,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.tint,
    required this.onTint,
    required this.value,
    required this.label,
  });

  final IconData icon;

  /// The chip behind [icon], and the ink drawn on it.
  final Color tint;
  final Color onTint;

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
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: AppRadius.smRadius,
                ),
                child: Icon(icon, size: 20, color: onTint),
              ),
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
    // Emerald that stays AA on the card in either theme.
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return AppCard(
      child: Row(
        children: [
          Semantics(
            container: true,
            label: '${result.topic.label} mastery: ${result.masteryAfter.label}'
                ', ${(result.masteryProgress * 100).round()}% to next level',
            child: ProgressRing(
              value: result.masteryProgress,
              progressColor: AppColors.primaryAction,
              child: ExcludeSemantics(
                child: Text(
                  result.masteryAfter.label.substring(0, 1),
                  style: AppTypography.headingSmall.copyWith(color: emerald),
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
                    color: emerald,
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
