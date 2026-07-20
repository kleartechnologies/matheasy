import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/services/haptics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../application/onboarding_controller.dart';
import '../../domain/onboarding_models.dart';
import '../widgets/onboarding_backdrop.dart';

/// A broad level band shown on the onboarding level picker, mapped to the
/// underlying [StudyLevel] that seeds the learner profile.
class _Band {
  const _Band({
    required this.level,
    required this.glyph,
    required this.title,
    required this.description,
    this.aiMatch = false,
  });

  final StudyLevel level;
  final String glyph;
  final String title;
  final String description;
  final bool aiMatch;
}

/// Onboarding 4/5 — "Learn at your own level." Four broad bands; picking one is
/// optional and seeds the profile's grade level.
class LevelSelectPage extends ConsumerWidget {
  const LevelSelectPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final l10n = context.l10n;
    final selected = ref.watch(onboardingFlowControllerProvider).level;

    final bands = [
      _Band(
        level: StudyLevel.primary,
        glyph: '2+2',
        title: l10n.onboardingBandPrimaryTitle,
        description: l10n.onboardingBandPrimaryDesc,
      ),
      _Band(
        level: StudyLevel.secondary,
        glyph: 'x²',
        title: l10n.onboardingBandSecondaryTitle,
        description: l10n.onboardingBandSecondaryDesc,
      ),
      _Band(
        level: StudyLevel.college,
        glyph: '∫dx',
        title: l10n.onboardingBandCollegeTitle,
        description: l10n.onboardingBandCollegeDesc,
      ),
      _Band(
        level: StudyLevel.university,
        glyph: 'Σ∂',
        title: l10n.onboardingBandUniversityTitle,
        description: l10n.onboardingBandUniversityDesc,
        aiMatch: true,
      ),
    ];

    return Stack(
      fit: StackFit.expand,
      children: [
        const OnboardingBackdrop(
          glyphs: [
            OnboardingGlyph('∫', Alignment(-0.85, -0.82), size: 34),
            OnboardingGlyph('Σ', Alignment(0.86, 0.52)),
          ],
        ),
        Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Column(
                  children: [
                    for (var i = 0; i < bands.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: AppTransitions.slideUp(
                          delay: Duration(milliseconds: 60 * i),
                          child: _LevelBandCard(
                            band: bands[i],
                            selected: selected == bands[i].level,
                            onTap: () {
                              HapticsService.selection();
                              ref
                                  .read(
                                    onboardingFlowControllerProvider.notifier,
                                  )
                                  .selectLevel(bands[i].level);
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            AppTransitions.slideUp(
              child: Column(
                children: [
                  Text(
                    l10n.onboardingLevelTitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.displaySmall.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.onboardingLevelSubtitle,
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyLarge.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LevelBandCard extends StatelessWidget {
  const _LevelBandCard({
    required this.band,
    required this.selected,
    required this.onTap,
  });

  final _Band band;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryDark;
    return Semantics(
      selected: selected,
      button: true,
      label: band.title,
      child: AppCard(
        onTap: onTap,
        elevated: !selected,
        color: selected ? colors.primaryContainer : colors.surface,
        border: Border.all(
          color: selected ? accent : colors.border,
          width: selected ? 2 : 1.5,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primaryAction
                    : colors.primaryContainer,
                borderRadius: AppRadius.mdRadius,
              ),
              child: Text(
                band.glyph,
                style: AppTypography.title.copyWith(
                  color: selected ? AppColors.white : accent,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    band.title,
                    style: AppTypography.title.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    band.description,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (band.aiMatch)
              _AiMatchBadge()
            else
              Icon(Icons.chevron_right_rounded, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _AiMatchBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: const BoxDecoration(
        color: AppColors.primaryAction,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        context.l10n.onboardingAiMatch.toUpperCase(),
        style: AppTypography.label.copyWith(color: AppColors.white),
      ),
    );
  }
}
