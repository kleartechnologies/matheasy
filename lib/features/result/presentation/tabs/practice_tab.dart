import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import '../widgets/difficulty_pill.dart';
import '../widgets/math_text.dart';
import '../widgets/result_empty.dart';

/// Tab 4 — similar practice questions grouped by difficulty. Tapping a card is
/// future interaction design only (sessions arrive in Stage 8).
class PracticeTab extends StatelessWidget {
  const PracticeTab({
    super.key,
    required this.questions,
    required this.onGenerateMore,
    required this.onOpenQuestion,
  });

  final List<PracticeQuestion> questions;
  final VoidCallback onGenerateMore;
  final VoidCallback onOpenQuestion;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const ResultEmpty(
        message: "No practice yet — tap Generate and I'll make some just for "
            'you!',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MatheasyBubble(
          text: 'Master it! Here are similar questions tuned to your level.',
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final difficulty in Difficulty.values)
          ..._group(context, difficulty),
        const SizedBox(height: AppSpacing.xs),
        PrimaryButton(
          label: 'Generate more like this',
          icon: Icons.auto_awesome_rounded,
          onPressed: onGenerateMore,
        ),
      ],
    );
  }

  List<Widget> _group(BuildContext context, Difficulty difficulty) {
    final items = questions.where((q) => q.difficulty == difficulty).toList();
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Text(
          difficulty.label,
          style: AppTypography.label.copyWith(
            color: context.colors.textTertiary,
          ),
        ),
      ),
      for (final question in items)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _PracticeCard(question: question, onTap: onOpenQuestion),
        ),
    ];
  }
}

class _PracticeCard extends StatelessWidget {
  const _PracticeCard({required this.question, required this.onTap});

  final PracticeQuestion question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: MathText(
              question.questionLatex,
              style:
                  AppTypography.headingSmall.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.xpContainer,
              borderRadius: AppRadius.smRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt_rounded, size: 14, color: AppColors.xp),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  '+${question.xpReward}',
                  style:
                      AppTypography.label.copyWith(color: AppColors.amber),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          DifficultyPill(question.difficulty),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.chevron_right_rounded, size: 22, color: colors.textTertiary),
        ],
      ),
    );
  }
}
