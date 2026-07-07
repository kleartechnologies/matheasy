import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

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
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AppTransitions.scaleIn(child: illustration),
          ),
        ),
        AppTransitions.slideUp(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Column(
              children: [
                Text(
                  headline,
                  textAlign: TextAlign.center,
                  style: AppTypography.displaySmall
                      .copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLarge
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared layout for the question pages: a title + optional subtitle, then a
/// scrollable stack of options.
class OnboardingQuestionLayout extends StatelessWidget {
  const OnboardingQuestionLayout({
    super.key,
    required this.question,
    required this.options,
    this.subtitle,
  });

  final String question;
  final String? subtitle;
  final List<Widget> options;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTransitions.slideUp(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: AppTypography.headingLarge
                    .copyWith(color: colors.textPrimary),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  subtitle!,
                  style: AppTypography.bodyMedium
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            itemCount: options.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, index) => options[index],
          ),
        ),
      ],
    );
  }
}
