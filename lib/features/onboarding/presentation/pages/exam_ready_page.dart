import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../widgets/onboarding_layouts.dart';

/// Page 5 — Exam Ready.
class ExamReadyPage extends StatelessWidget {
  const ExamReadyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OnboardingIntroLayout(
      headline: 'Built For Your Exams',
      subtitle: 'Personalized help tuned to SPM, IGCSE, GCSE, SAT and more.',
      illustration: _ExamArt(),
    );
  }
}

class _ExamArt extends StatelessWidget {
  const _ExamArt();

  // Each colour is painted as the card's heading text, so the emerald entry
  // resolves per theme — the identity emerald is 2.97:1 and would fail here.
  static List<(String, String, Color)> _exams(BuildContext context) => [
        (
          'SPM',
          'Malaysia',
          context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
        ),
        ('IGCSE', 'Cambridge', AppColors.secondary),
        ('GCSE', 'UK', AppColors.accentAmber),
        ('SAT', 'College', AppColors.accentCoral),
      ];

  @override
  Widget build(BuildContext context) {
    final exams = _exams(context);
    return SizedBox(
      width: 280,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < 2; row++) ...[
            if (row > 0) const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(child: _ExamCard(exams[row * 2])),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _ExamCard(exams[row * 2 + 1])),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard(this.data);

  final (String, String, Color) data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            data.$1,
            style: AppTypography.headingMedium.copyWith(color: data.$3),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            data.$2,
            style: AppTypography.caption
                .copyWith(color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
