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

/// The session-complete screen (V5): accuracy, XP, time and hints, mastery
/// progress, what was strong and what needs review, and the engine's
/// "practice this next" — the student leaves knowing exactly what to improve.
class PracticeResultsView extends StatelessWidget {
  const PracticeResultsView({
    super.key,
    required this.result,
    required this.onContinue,
    required this.onDone,
    this.onPracticeRecommended,
  });

  final PracticeResult result;
  final VoidCallback onContinue;
  final VoidCallback onDone;

  /// Starts a session targeted at [PracticeResult.recommendedNext]; the CTA
  /// hides when null (free tier / no recommendation).
  final VoidCallback? onPracticeRecommended;

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
          _summary(context, result),
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
        if (result.timeSpentSeconds > 0 || result.hintsUsedTotal > 0) ...[
          const SizedBox(height: AppSpacing.md),
          AppTransitions.slideUp(
            delay: AppDurations.medium,
            child: _JourneyRow(result: result),
          ),
        ],
        if (result.strongSkills.isNotEmpty ||
            result.weakSkills.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppTransitions.slideUp(
            delay: AppDurations.medium,
            child: _SkillsCard(result: result),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        if (result.recommendedNext case final rec?
            when onPracticeRecommended != null) ...[
          PrimaryButton(
            label: context.l10n.practiceRecommendedNextCta(rec.skill.label),
            icon: Icons.auto_awesome_rounded,
            onPressed: onPracticeRecommended,
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: context.l10n.practiceKeepPracticing,
            icon: Icons.replay_rounded,
            onPressed: onContinue,
          ),
        ] else
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

  String _summary(BuildContext context, PracticeResult result) {
    if (result.isPerfect) {
      return context.l10n.practiceSummaryPerfect(result.topic.label);
    }
    if (result.accuracy >= 0.6) {
      return context.l10n.practiceSummaryGood(result.topic.label);
    }
    return context.l10n.practiceSummaryKeepGoing(result.topic.label);
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

/// Time spent + hints used — the journey behind the score.
class _JourneyRow extends StatelessWidget {
  const _JourneyRow({required this.result});

  final PracticeResult result;

  static String _time(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;
    return rest == 0 ? '${minutes}m' : '${minutes}m ${rest}s';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            icon: Icons.timer_outlined,
            tint: colors.infoContainer,
            onTint: colors.onInfoContainer,
            value: _time(result.timeSpentSeconds),
            label: context.l10n.practiceStatTime,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _StatTile(
            icon: Icons.lightbulb_outline_rounded,
            tint: colors.warningContainer,
            onTint: colors.onWarningContainer,
            value: '${result.hintsUsedTotal}',
            label: context.l10n.practiceStatHints,
          ),
        ),
      ],
    );
  }
}

/// What went well and what to review, as skill chips — the spec's
/// "students should leave knowing exactly what to improve".
class _SkillsCard extends StatelessWidget {
  const _SkillsCard({required this.result});

  final PracticeResult result;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (result.strongSkills.isNotEmpty) ...[
            Text(
              context.l10n.practiceStrongThisSession,
              style: AppTypography.label.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final skill in result.strongSkills)
                  _SkillChip(
                    label: skill,
                    tint: colors.successContainer,
                    onTint: colors.onSuccessContainer,
                    icon: Icons.check_rounded,
                  ),
              ],
            ),
          ],
          if (result.strongSkills.isNotEmpty && result.weakSkills.isNotEmpty)
            const SizedBox(height: AppSpacing.lg),
          if (result.weakSkills.isNotEmpty) ...[
            Text(
              context.l10n.practiceConceptsToReview,
              style: AppTypography.label.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final skill in result.weakSkills)
                  _SkillChip(
                    label: skill,
                    tint: colors.warningContainer,
                    onTint: colors.onWarningContainer,
                    icon: Icons.menu_book_rounded,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SkillChip extends StatelessWidget {
  const _SkillChip({
    required this.label,
    required this.tint,
    required this.onTint,
    required this.icon,
  });

  final String label;
  final Color tint;
  final Color onTint;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: AppRadius.pillRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: onTint),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: AppTypography.label.copyWith(color: onTint),
          ),
        ],
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
            label: context.l10n.practiceMasterySemantics(
              result.topic.label,
              result.masteryAfter.label,
              (result.masteryProgress * 100).round(),
            ),
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
                  context.l10n.practiceTopicMastery(result.topic.label),
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
                      context.l10n.practiceLevelUp(
                        result.masteryBefore.label,
                        result.masteryAfter.label,
                      ),
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
