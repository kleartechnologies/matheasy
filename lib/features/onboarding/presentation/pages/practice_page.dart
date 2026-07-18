import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 4 — Practice & Improve.
class PracticePage extends StatelessWidget {
  const PracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingIntroLayout(
      headline: context.l10n.onboardingPracticeHeadline,
      subtitle: context.l10n.onboardingPracticeSubtitle,
      illustration: const _PracticeArt(),
    );
  }
}

class _PracticeArt extends StatelessWidget {
  const _PracticeArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StreakCard(days: 12),
          const SizedBox(height: AppSpacing.md),
          AchievementCard(
            icon: Icons.workspace_premium_rounded,
            title: context.l10n.onboardingAchievementTitle,
            subtitle: '10 correct answers in a row',
            unlocked: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          const XPProgressBar(value: 0.72, label: 'Level 7 · 360 XP to level 8'),
        ],
      ),
    );
  }
}
