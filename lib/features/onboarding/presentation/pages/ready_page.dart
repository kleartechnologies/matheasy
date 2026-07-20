import 'package:flutter/material.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/brand/brand.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/onboarding_backdrop.dart';
import '../widgets/onboarding_layouts.dart';

/// Onboarding 5/5 — the finale. The brand mark with a verified check, orbited by
/// mastered-topic pills. The dual CTA lives in the host action bar.
class ReadyPage extends StatelessWidget {
  const ReadyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingHeroPage(
      glyphs: const [
        OnboardingGlyph('π', Alignment(0.82, -0.78), accent: true),
        OnboardingGlyph('√', Alignment(0.78, 0.7), size: 34),
        OnboardingGlyph('∞', Alignment(-0.84, 0.5), size: 28),
      ],
      illustration: const _ReadyArt(),
      headline: context.l10n.onboardingReadyTitle,
      subtitle: context.l10n.onboardingReadySubtitle,
    );
  }
}

class _ReadyArt extends StatelessWidget {
  const _ReadyArt();

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final l10n = context.l10n;
    return SizedBox(
      width: 300,
      height: 290,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Soft emerald aura behind the mark.
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.22),
                  AppColors.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          Floaty(
            enabled: !reduced,
            child: const SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  MatheasyBrandAvatar(size: 150),
                  Positioned(right: -6, bottom: -6, child: _CheckBadge()),
                ],
              ),
            ),
          ),
          Positioned(
            top: 24,
            left: 0,
            child: _TopicPill(
              label: l10n.onboardingChipAlgebra,
              enabled: !reduced,
              period: 5200,
            ),
          ),
          Positioned(
            top: 118,
            right: -8,
            child: _TopicPill(
              label: l10n.onboardingChipFractions,
              enabled: !reduced,
              period: 6100,
            ),
          ),
          Positioned(
            bottom: 30,
            left: 14,
            child: _TopicPill(
              label: l10n.onboardingChipGeometry,
              enabled: !reduced,
              period: 4700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        boxShadow: context.elevation.floating,
      ),
      child: const Icon(
        Icons.check_rounded,
        size: 28,
        color: AppColors.primaryAction,
      ),
    );
  }
}

class _TopicPill extends StatelessWidget {
  const _TopicPill({
    required this.label,
    required this.enabled,
    required this.period,
  });

  final String label;
  final bool enabled;
  final int period;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryDark;
    return Floaty(
      enabled: enabled,
      amplitude: 5,
      period: Duration(milliseconds: period),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadius.pillRadius,
          boxShadow: context.elevation.raised,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 17, color: accent),
            const SizedBox(width: AppSpacing.xs + 2),
            Text(
              label,
              style: AppTypography.caption.copyWith(color: colors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
