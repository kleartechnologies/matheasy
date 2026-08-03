import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/chat/rich_math_text.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../result/presentation/widgets/math_text.dart';
import '../../domain/tutor_models.dart';

/// Numi's explanation, rendered as a short stack of cards instead of one long
/// paragraph: 🎯 goal → ① ② ③ steps → 💡 why it works → ⚠️ common mistake →
/// 🎓 the verified answer.
///
/// The point is READABILITY, not new maths. Every card here draws content the
/// server already gated: an `equation` reached this widget only because it
/// matched a verified line character-for-character (whitespace aside) or is a
/// closed arithmetic identity mathjs checked, and `finalAnswer` is the app's own
/// verified string — the model's characters are never printed. Prose fields may
/// carry inline `$…$`, so they go through [RichMathText]; standalone equations
/// are pure LaTeX and go through [MathText]/[AdaptiveMath].
///
/// Every section renders only when it has content, so a framing-only lesson
/// (Hint mode: a goal and a nudge, no route to the answer) is a two-card stack
/// and nothing more.
class TutorLessonView extends StatelessWidget {
  const TutorLessonView(this.lesson, {super.key});

  final TutorLesson lesson;

  @override
  Widget build(BuildContext context) {
    final concept = lesson.concept;
    final mistake = lesson.commonMistake;
    final answer = lesson.finalAnswer;

    final sections = <Widget>[
      _GoalCard(lesson.goal),
      for (var i = 0; i < lesson.steps.length; i++)
        _StepCard(step: lesson.steps[i], number: i + 1),
      if (concept != null && concept.isNotEmpty) _ConceptCard(concept),
      if (mistake != null && mistake.isNotEmpty) _MistakeCard(mistake),
      if (answer != null && answer.isNotEmpty) _AnswerCard(answer),
    ];

    return Semantics(
      container: true,
      label: context.l10n.tutorLessonLabel,
      // Each card keeps its own node: a lesson is navigated card by card, not
      // heard as one 200-word run-on. Without this the group label swallows
      // every child — including the equations' spoken form.
      explicitChildNodes: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            sections[i],
          ],
        ],
      ),
    );
  }
}

/// The emerald that stays legible as a label on a card, per theme (CLAUDE.md:
/// `AppColors.primary` is the identity tone and never a text colour).
Color _emerald(BuildContext context) =>
    context.isDark ? AppColors.primaryLight : AppColors.primaryDark;

/// A section heading: emoji + a short all-caps label, the same everywhere.
class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.emoji, required this.label, this.color});

  final String emoji;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label.toUpperCase(),
            style: AppTypography.label.copyWith(
              color: color ?? _emerald(context),
              letterSpacing: 0.3,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 🎯 Goal — one sentence on what we are trying to achieve
// ---------------------------------------------------------------------------

class _GoalCard extends StatelessWidget {
  const _GoalCard(this.goal);

  final String goal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            emoji: '🎯',
            label: context.l10n.tutorLessonGoal,
            color: colors.onPrimaryContainer,
          ),
          const SizedBox(height: AppSpacing.xs),
          RichMathText(
            goal,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ① ② ③ Steps — a short instruction, a line of words, one transformation
// ---------------------------------------------------------------------------

class _StepCard extends StatelessWidget {
  const _StepCard({required this.step, required this.number});

  final TutorLessonStep step;
  final int number;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final equation = step.equation;
    final showExplanation =
        step.explanation.isNotEmpty && step.explanation != step.title;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The step number, spoken as "Step 3" rather than as a bare digit.
          Semantics(
            label: context.l10n.tutorLessonStepLabel(number),
            excludeSemantics: true,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$number',
                style: AppTypography.caption.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // Optical centring against the 24pt badge.
                  padding: const EdgeInsets.only(top: 2),
                  child: RichMathText(
                    step.title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ),
                if (showExplanation) ...[
                  const SizedBox(height: AppSpacing.xs),
                  RichMathText(
                    step.explanation,
                    style: AppTypography.bodySmall.copyWith(
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ],
                // The transformation gets its own line, on its own surface —
                // one move per step, so the eye can follow the maths down the
                // page without reading a word.
                if (equation != null && equation.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceMuted,
                      borderRadius: AppRadius.mdRadius,
                    ),
                    child: AdaptiveMath(
                      equation,
                      style: AppTypography.headingSmall.copyWith(
                        color: colors.textPrimary,
                      ),
                      minFontSize: 14,
                      maxFontSize: 20,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 💡 Why this works — the concept, in a sentence or two
// ---------------------------------------------------------------------------

class _ConceptCard extends StatelessWidget {
  const _ConceptCard(this.concept);

  final String concept;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(emoji: '💡', label: context.l10n.tutorLessonWhy),
          const SizedBox(height: AppSpacing.xs),
          RichMathText(
            concept,
            style: AppTypography.bodySmall.copyWith(
              color: colors.textPrimary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ⚠️ Common mistake — the trap, named before it is fallen into
// ---------------------------------------------------------------------------

class _MistakeCard extends StatelessWidget {
  const _MistakeCard(this.mistake);

  final String mistake;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            emoji: '⚠️',
            label: context.l10n.tutorLessonMistake,
            color: colors.onWarningContainer,
          ),
          const SizedBox(height: AppSpacing.xs),
          RichMathText(
            mistake,
            style: AppTypography.bodySmall.copyWith(
              color: colors.onWarningContainer,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 🎓 Final answer — the app's verified string, never the model's
// ---------------------------------------------------------------------------

class _AnswerCard extends StatelessWidget {
  const _AnswerCard(this.answer);

  final String answer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.cardRadius,
        border: const Border(
          left: BorderSide(color: AppColors.gold, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            emoji: '🎓',
            label: context.l10n.tutorLessonAnswer,
            color: colors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.xs),
          AdaptiveMath(
            answer,
            style: AppTypography.headingSmall.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            minFontSize: 16,
            maxFontSize: 24,
          ),
        ],
      ),
    );
  }
}
