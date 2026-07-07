import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 4 — Practice & Improve.
class PracticePage extends StatelessWidget {
  const PracticePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingIntroLayout(
      headline: 'Practice Until You Master It',
      subtitle: 'Unlimited practice, XP, streaks and achievements keep you '
          'motivated every day.',
      illustration: _PracticeArt(),
    );
  }
}

class _PracticeArt extends StatelessWidget {
  const _PracticeArt();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreakCard(days: 12),
          SizedBox(height: AppSpacing.md),
          AchievementCard(
            icon: Icons.workspace_premium_rounded,
            title: 'Sharp Shooter',
            subtitle: '10 correct answers in a row',
            unlocked: true,
          ),
          SizedBox(height: AppSpacing.lg),
          XPProgressBar(value: 0.72, label: 'Level 7 · 360 XP to level 8'),
        ],
      ),
    );
  }
}
