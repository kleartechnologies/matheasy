import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'onboarding_backdrop.dart';

/// Shared layout for the value-proposition / hero pages: a large illustration
/// stage on top, headline + subtitle beneath. Content animates in on build.
class OnboardingIntroLayout extends StatelessWidget {
  const OnboardingIntroLayout({
    super.key,
    required this.illustration,
    required this.headline,
    required this.subtitle,
  });

  final Widget illustration;
  final String headline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Centre the illustration over the headline when there's room, but fall
    // back to a scroll view so a large textScaler can never overflow the fixed
    // PageView viewport (the illustration text block is otherwise inflexible).
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      // scaleDown keeps the fixed-size illustration cards from
                      // overflowing narrow screens (never enlarges); the
                      // decorative math is hidden from screen readers — the
                      // headline + subtitle carry the meaning.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ExcludeSemantics(
                          child: AppTransitions.scaleIn(child: illustration),
                        ),
                      ),
                    ),
                  ),
                ),
                AppTransitions.slideUp(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: Column(
                      children: [
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: AppTypography.displaySmall.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          subtitle,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A full onboarding hero page: the ambient math backdrop behind an
/// [OnboardingIntroLayout]. Every value-prop screen composes this so the drift
/// motif and the illustration/headline rhythm stay identical across pages.
class OnboardingHeroPage extends StatelessWidget {
  const OnboardingHeroPage({
    super.key,
    required this.glyphs,
    required this.illustration,
    required this.headline,
    required this.subtitle,
  });

  final List<OnboardingGlyph> glyphs;
  final Widget illustration;
  final String headline;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        OnboardingBackdrop(glyphs: glyphs),
        OnboardingIntroLayout(
          illustration: illustration,
          headline: headline,
          subtitle: subtitle,
        ),
      ],
    );
  }
}
