import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/onboarding_backdrop.dart';
import '../widgets/onboarding_layouts.dart';

/// Onboarding 2/5 — "Watch every step come to life." A solver card whose active
/// step advances on its own, one line at a time.
class StepsIntroPage extends StatelessWidget {
  const StepsIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingHeroPage(
      glyphs: const [
        OnboardingGlyph('Δ', Alignment(0.82, -0.7)),
        OnboardingGlyph('÷', Alignment(-0.84, 0.66), size: 32),
        OnboardingGlyph('π', Alignment(0.8, 0.8), size: 26),
      ],
      illustration: const _StepsCard(),
      headline: context.l10n.onboardingStepsTitle,
      subtitle: context.l10n.onboardingStepsSubtitle,
    );
  }
}

class _StepsCard extends StatefulWidget {
  const _StepsCard();

  @override
  State<_StepsCard> createState() => _StepsCardState();
}

class _StepsCardState extends State<_StepsCard>
    with SingleTickerProviderStateMixin {
  static const List<String> _steps = [
    '2x + 6 = 14',
    '2x = 14 - 6',
    '2x = 8',
    'x = 4',
  ];

  // One full cycle steps through all four lines, then loops. Derived from a
  // controller (not a Timer) so no timer is left pending during widget tests.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5600),
  );

  @override
  void initState() {
    super.initState();
    _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && _ctrl.isAnimating) {
      _ctrl.stop();
    } else if (!reduced && !_ctrl.isAnimating) {
      _ctrl.repeat();
    }
    // These emerald tiles carry white content (play glyph / step number), so
    // they use the white-bearing primaryAction (4.78:1) in BOTH themes — the
    // on-dark accent primaryLight would drop white to ~1.7:1.
    const accent = AppColors.primaryAction;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.lgRadius,
        boxShadow: context.elevation.card,
      ),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final active = reduced
              ? 1
              : (_ctrl.value * _steps.length).floor().clamp(0, 3);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: accent,
                      borderRadius: AppRadius.xsRadius,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 18,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${context.l10n.onboardingSolvingLabel.toUpperCase()} · '
                    '${context.l10n.onboardingStepCounter(active + 1, _steps.length).toUpperCase()}',
                    style: AppTypography.monoLabel.copyWith(
                      color: colors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (var i = 0; i < _steps.length; i++)
                _StepRow(index: i, equation: _steps[i], active: i == active),
            ],
          );
        },
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.index,
    required this.equation,
    required this.active,
  });

  final int index;
  final String equation;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // These emerald tiles carry white content (play glyph / step number), so
    // they use the white-bearing primaryAction (4.78:1) in BOTH themes — the
    // on-dark accent primaryLight would drop white to ~1.7:1.
    const accent = AppColors.primaryAction;
    return AnimatedContainer(
      duration: AppDurations.medium,
      curve: AppCurves.standard,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: active ? colors.primaryContainer : Colors.transparent,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: AppDurations.medium,
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? accent : colors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${index + 1}',
              style: AppTypography.caption.copyWith(
                color: active ? AppColors.white : colors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            equation,
            style: AppTypography.mono.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: active ? colors.onPrimaryContainer : colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
