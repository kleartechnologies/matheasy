import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/practice_session.dart';
import 'practice_chips.dart';

/// The header above a question: progress, the question count, and the current
/// question's difficulty + XP, plus a (non-functional) timer placeholder that a
/// later stage wires up.
class PracticeSessionHeader extends StatelessWidget {
  const PracticeSessionHeader({super.key, required this.session});

  final PracticeSession session;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final question = session.currentQuestion;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Question ${session.questionNumber} of ${session.total}',
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            const _TimerPlaceholder(),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        XPProgressBar(value: session.progress),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            PracticeDifficultyPill(question.difficulty),
            const SizedBox(width: AppSpacing.sm),
            PracticeXpBadge(xp: question.xpReward),
          ],
        ),
      ],
    );
  }
}

/// A placeholder timer chip — the countdown itself arrives in a later stage.
class _TimerPlaceholder extends StatelessWidget {
  const _TimerPlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Untimed practice',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_outlined,
              size: 14,
              color: colors.textMuted,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              'No timer',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
