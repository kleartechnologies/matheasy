import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/result_models.dart';

/// V3 · SECTION 5 — the Quick Summary that closes the lesson.
///
/// Three cards, hard-capped: *method used*, *remember this*, *watch out for*.
/// It is the takeaway a student would write in the margin — not a recap of the
/// whole page. Everything that didn't make the cut lives in "Learn more".
class LessonSummary extends StatelessWidget {
  const LessonSummary({
    super.key,
    required this.result,
    required this.methodName,
    required this.onReplay,
  });

  final ResultData result;

  /// The method the learner actually walked through — the teaching layer's
  /// choice may differ from the selected method chip, so the caller decides.
  final String methodName;

  final VoidCallback onReplay;

  /// The hard cap from the brief. Three is a summary; four is a page.
  static const int maxCards = 3;

  List<_SummaryCardData> _cards(BuildContext context) {
    final l10n = context.l10n;
    final teaching = result.teaching;
    final cards = <_SummaryCardData>[];

    // 1 — What we did. Prefer the teaching layer's phrasing (it names the
    // method the way a teacher would), else the selected method's own name.
    final chosen = teaching?.header.methodChosen.trim() ?? '';
    final label = chosen.isNotEmpty ? chosen : methodName.trim();
    if (label.isNotEmpty) {
      cards.add(_SummaryCardData(
        icon: Icons.route_rounded,
        eyebrow: l10n.solutionMethodUsed,
        headline: label,
        body: teaching?.header.whyMethodChosen.trim(),
        tone: _SummaryTone.neutral,
      ));
    }

    // 2 — The one sentence worth carrying to the next problem.
    final takeaway = teaching?.keyTakeaway;
    if (takeaway != null && takeaway.headline.trim().isNotEmpty) {
      cards.add(_SummaryCardData(
        icon: Icons.lightbulb_rounded,
        eyebrow: l10n.teachingRememberThis,
        headline: takeaway.headline.trim(),
        body: takeaway.detail?.trim(),
        tone: _SummaryTone.emerald,
      ));
    }

    // 3 — The single trap most likely to bite here. Only the first: a list of
    // mistakes is a lesson of its own, and that one lives in "Learn more".
    final mistake = teaching?.commonMistakes
        .where((m) => m.mistake.trim().isNotEmpty)
        .firstOrNull;
    if (mistake != null) {
      cards.add(_SummaryCardData(
        icon: Icons.warning_amber_rounded,
        eyebrow: l10n.teachingWatchOutFor,
        headline: mistake.mistake.trim(),
        body: mistake.fix.trim().isNotEmpty ? mistake.fix.trim() : null,
        tone: _SummaryTone.warning,
      ));
    }

    return cards.take(maxCards).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final cards = _cards(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The completion beat — quiet, not confetti. The reward is the practice
        // invite that follows.
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.successContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded,
                  size: 19, color: colors.onSuccessContainer),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.solutionLessonComplete,
                    style: AppTypography.title
                        .copyWith(color: colors.textPrimary),
                  ),
                  Text(
                    context.l10n.solutionLessonCompleteSubtitle,
                    style: AppTypography.caption
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (cards.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _SummaryCard(data: cards[i]),
          ],
        ],
        // The substitution check, in one line. It is proof, not a lesson — so it
        // gets caption weight, not a card of its own.
        if (result.verifyText.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_rounded, size: 14, color: emerald),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  result.verifyText.trim(),
                  style:
                      AppTypography.caption.copyWith(color: colors.textMuted),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          button: true,
          label: context.l10n.solutionReplayLesson,
          excludeSemantics: true,
          child: Pressable(
            onTap: onReplay,
            borderRadius: AppRadius.smRadius,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.replay_rounded, size: 16, color: emerald),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    context.l10n.solutionReplayLesson,
                    style: AppTypography.caption.copyWith(
                      color: emerald,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _SummaryTone { neutral, emerald, warning }

class _SummaryCardData {
  const _SummaryCardData({
    required this.icon,
    required this.eyebrow,
    required this.headline,
    required this.body,
    required this.tone,
  });

  final IconData icon;
  final String eyebrow;
  final String headline;
  final String? body;
  final _SummaryTone tone;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data});

  final _SummaryCardData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color bg, Color ink) = switch (data.tone) {
      _SummaryTone.neutral => (colors.surfaceMuted, colors.textSecondary),
      _SummaryTone.emerald => (
          colors.primaryContainer,
          colors.onPrimaryContainer
        ),
      _SummaryTone.warning => (
          colors.warningContainer,
          colors.onWarningContainer
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.mdRadius),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, size: 16, color: ink),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.eyebrow.toUpperCase(),
                  style: AppTypography.label.copyWith(color: ink),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  data.headline,
                  style: AppTypography.bodySmall.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (data.body != null && data.body!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    data.body!,
                    style: AppTypography.caption
                        .copyWith(color: colors.textSecondary, height: 1.4),
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
