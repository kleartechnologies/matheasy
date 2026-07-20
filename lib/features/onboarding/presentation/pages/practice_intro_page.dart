import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_backdrop.dart';
import '../widgets/onboarding_layouts.dart';

/// Onboarding 3/5 — "Practice until you master it." An XP progress ring counting
/// up, a rising activity chart, and a floating streak badge.
class PracticeIntroPage extends StatelessWidget {
  const PracticeIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingHeroPage(
      glyphs: const [
        OnboardingGlyph('√', Alignment(-0.86, -0.66), size: 31),
        OnboardingGlyph('Σ', Alignment(0.84, 0.7), size: 28),
        OnboardingGlyph('∞', Alignment(-0.8, 0.78), size: 26),
      ],
      illustration: const _PracticeCard(),
      headline: context.l10n.onboardingPracticeTitle,
      subtitle: context.l10n.onboardingPracticeSubtitle,
    );
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard();

  static const int _level = 7;
  static const int _xp = 1240;
  static const int _toNext = 760;
  static const double _ringValue = 0.62;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final accent = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryDark;

    return SizedBox(
      width: 268,
      child: Padding(
        // Reserve the top-right overhang so the streak badge stays inside the
        // root bounds (a scaleDown FittedBox would otherwise clip it).
        padding: const EdgeInsets.only(top: 18, right: 10),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xxl,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: AppRadius.xlRadius,
                boxShadow: context.elevation.card,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ProgressRing(
                    value: _ringValue,
                    size: 148,
                    strokeWidth: 12,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          context.l10n
                              .onboardingLevelBadge(_level)
                              .toUpperCase(),
                          style: AppTypography.label.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _CountUp(
                          value: _xp,
                          reduced: reduced,
                          style: AppTypography.numeric.copyWith(
                            fontSize: 30,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          context.l10n.onboardingXpUnit,
                          style: AppTypography.label.copyWith(color: accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    context.l10n.onboardingXpToNext(_toNext, _level + 1),
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _ActivityBars(reduced: reduced),
                ],
              ),
            ),
            const Positioned(
              top: -18,
              right: -10,
              child: _StreakBadge(days: 12),
            ),
          ],
        ),
      ),
    );
  }
}

/// A locale-formatted integer that tweens up from zero (so "1240" reads as the
/// viewer's "1,240"). Freezes at the final value under reduced motion.
class _CountUp extends StatelessWidget {
  const _CountUp({
    required this.value,
    required this.style,
    required this.reduced,
  });

  final int value;
  final TextStyle style;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final format = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toString(),
    );
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: reduced ? Duration.zero : AppDurations.verySlow,
      curve: AppCurves.standard,
      builder: (context, current, _) =>
          Text(format.format(current), style: style),
    );
  }
}

class _ActivityBars extends StatelessWidget {
  const _ActivityBars({required this.reduced});

  final bool reduced;

  static const List<double> _heights = [0.35, 0.5, 0.42, 0.62, 0.72, 0.88, 1.0];

  @override
  Widget build(BuildContext context) {
    final strong = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryAction;
    final soft = context.isDark
        ? AppColors.primaryLight.withValues(alpha: 0.32)
        : AppColors.primaryTint;
    return SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _heights.length; i++) ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: reduced ? _heights[i] : 0, end: _heights[i]),
              duration: reduced
                  ? Duration.zero
                  : Duration(milliseconds: 500 + i * 90),
              curve: AppCurves.emphasized,
              builder: (context, t, _) => Container(
                width: 11,
                height: 52 * t,
                decoration: BoxDecoration(
                  color: i >= 5 ? strong : soft,
                  borderRadius: AppRadius.smRadius,
                ),
              ),
            ),
            if (i != _heights.length - 1) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days});

  final int days;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdRadius,
        boxShadow: context.elevation.raised,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.streak,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$days',
              style: AppTypography.title.copyWith(color: AppColors.white),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 58),
            child: Text(
              context.l10n.onboardingDayStreak.toUpperCase(),
              style: AppTypography.label.copyWith(
                color: colors.textPrimary,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
