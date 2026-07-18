import 'package:flutter/material.dart';

import '../../../../../core/animations/pressable.dart';
import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/localization/l10n_extension.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_durations.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/teaching_models.dart';
import '../math_text.dart';

/// STAGE 16 — the Learning Journey cards (spec §5/§6).
///
/// The additive teaching layer, rendered around the frozen verified solution.
/// EVERY card renders only when its model has content — a v1 payload (no
/// teaching) shows none of them, so the Solution tab is unchanged. Prose fields
/// use plain [Text] (they may contain inline unicode math but are not LaTeX);
/// only genuine LaTeX (`givens`, practice items) goes through [MathText].
///
/// Colour discipline (CLAUDE.md): emerald text takes `primaryDark`/`primaryLight`
/// per theme (never `AppColors.primary`, which is the 2.97:1 logo tone); filled
/// controls take `primaryAction`; mistakes use `warningContainer`, fixes
/// `successContainer`, the takeaway `gold`.

/// The emerald that stays legible as a label on a card, per theme.
Color _emerald(BuildContext context) =>
    context.isDark ? AppColors.primaryLight : AppColors.primaryDark;

// ---------------------------------------------------------------------------
// 1. Header — breadcrumb + learning objective
// ---------------------------------------------------------------------------

class TeachingHeaderCard extends StatelessWidget {
  const TeachingHeaderCard({super.key, required this.header});

  final TeachingHeader header;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final crumbs = <String>[
      header.categoryLabel,
      if (header.subcategory.isNotEmpty) header.subcategory,
      header.difficulty.label,
    ];
    final objective = header.learningObjective;
    return Semantics(
      container: true,
      label: 'Topic: ${crumbs.join(", ")}.'
          '${objective.isEmpty ? "" : " Goal: $objective"}',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        // Theme-aware container/on-container so BOTH the crumb and the objective
        // stay legible in dark mode (a fixed mint tint failed the objective text
        // at 1.25:1 — review #1).
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: AppRadius.cardRadius,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              crumbs.join('  ›  '),
              style: AppTypography.label.copyWith(
                color: colors.onPrimaryContainer,
                letterSpacing: 0.2,
              ),
            ),
            if (objective.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🎯', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      objective,
                      style: AppTypography.bodyMedium.copyWith(
                        color: colors.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Concept overview — first-principles hook + jargon + what's asked
// ---------------------------------------------------------------------------

class ConceptOverviewCard extends StatelessWidget {
  const ConceptOverviewCard({
    super.key,
    required this.concept,
    required this.overview,
  });

  final ConceptOverview concept;
  final ProblemOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧠', style: TextStyle(fontSize: 16)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.teachingTheIdea,
                style: AppTypography.label.copyWith(color: _emerald(context)),
              ),
            ],
          ),
          if (concept.body.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              concept.body,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textPrimary,
                height: 1.45,
              ),
            ),
          ],
          if (concept.definedTerms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final t in concept.definedTerms) _JargonChip(term: t),
              ],
            ),
          ],
          if (overview.asked.isNotEmpty || overview.predictionPrompt.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: colors.divider),
            const SizedBox(height: AppSpacing.md),
            if (overview.asked.isNotEmpty)
              _OverviewRow(
                  label: context.l10n.teachingWhatItAsks,
                  value: overview.asked),
            if (overview.goal.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _OverviewRow(
                  label: context.l10n.teachingThePlan, value: overview.goal),
            ],
            if (overview.predictionPrompt.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              // The prediction is a THINK-FIRST nudge (a question — never asserted
              // as fact); it is exempt from the numeric firewall by design.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('🤔', style: TextStyle(fontSize: 15)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      overview.predictionPrompt,
                      style: AppTypography.bodySmall.copyWith(
                        color: colors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A tap-to-reveal vocabulary chip: shows the term; tapping expands its plain
/// definition inline (self-explanation of jargon just-in-time).
class _JargonChip extends StatefulWidget {
  const _JargonChip({required this.term});

  final DefinedTerm term;

  @override
  State<_JargonChip> createState() => _JargonChipState();
}

class _JargonChipState extends State<_JargonChip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      expanded: _open,
      label: '${widget.term.term}: ${widget.term.plain}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => setState(() => _open = !_open),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppDurations.fast,
          constraints: BoxConstraints(
            minHeight: 44, // a11y tap target
            maxWidth: MediaQuery.sizeOf(context).width - 2 * AppSpacing.screenH,
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs + 1,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: AppRadius.pillRadius,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.term.term,
                      style: AppTypography.label
                          .copyWith(color: colors.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    _open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.help_outline_rounded,
                    size: 14,
                    color: colors.onPrimaryContainer,
                  ),
                ],
              ),
              if (_open) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.term.plain,
                  style: AppTypography.caption
                      .copyWith(color: colors.onPrimaryContainer),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  const _OverviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: AppTypography.label.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(color: colors.textPrimary),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Learning journey rail — the arc of the solution (a roadmap, not a stepper)
// ---------------------------------------------------------------------------

class LearningJourneyRail extends StatelessWidget {
  const LearningJourneyRail({
    super.key,
    required this.journey,
    required this.stepCount,
  });

  final List<JourneyStage> journey;

  /// Number of steps on screen — journey [stepIndices] are clamped against this
  /// so a malformed/foreign index can never be indexed into `steps` downstream
  /// (Phase 2 review residual).
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Keep the fixed stage order; a stage is "active" if it points at a real step.
    final stages = journey
        .map((s) => (
              stage: s,
              hasSteps: s.stepIndices.any((i) => i >= 0 && i < stepCount),
            ))
        .toList();
    if (stages.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: 'Learning journey: ${stages.map((s) => s.stage.id.label).join(", ")}',
      excludeSemantics: true,
      child: SizedBox(
        height: 58,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: stages.length,
          itemBuilder: (context, i) {
            final s = stages[i];
            final active = s.hasSteps;
            return Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primaryAction
                            : colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        active
                            ? Icons.check_rounded
                            : Icons.circle_outlined,
                        size: 13,
                        color: active
                            ? AppColors.white
                            : colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      s.stage.id.label,
                      style: AppTypography.caption.copyWith(
                        color: active ? colors.textPrimary : colors.textMuted,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
                if (i < stages.length - 1)
                  Container(
                    width: AppSpacing.md,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: colors.border,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Why this method — the metacognition card
// ---------------------------------------------------------------------------

class WhyThisMethodCard extends StatelessWidget {
  const WhyThisMethodCard({
    super.key,
    required this.header,
    required this.rationale,
    this.onCompare,
  });

  final TeachingHeader header;
  final MethodRationale rationale;

  /// Opens the Methods tab to compare approaches (null → the link is hidden).
  final VoidCallback? onCompare;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 18, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  header.methodChosen.isEmpty
                      ? context.l10n.teachingWhyThisMethod
                      : header.methodChosen,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (header.whyMethodChosen.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              header.whyMethodChosen,
              style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
          if (rationale.alternatives.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final alt in rationale.alternatives) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.alt_route_rounded,
                      size: 15, color: colors.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: AppTypography.caption
                            .copyWith(color: colors.textSecondary),
                        children: [
                          TextSpan(
                            text: alt.name,
                            style: TextStyle(
                              color: colors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (alt.whenBetter.isNotEmpty)
                            TextSpan(text: ' — ${alt.whenBetter}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (onCompare != null)
              _TextLink(
                  label: context.l10n.teachingCompareMethods,
                  onTap: onCompare!),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Common mistakes — the refutation triples
// ---------------------------------------------------------------------------

class CommonMistakesCard extends StatelessWidget {
  const CommonMistakesCard({super.key, required this.mistakes});

  final List<CommonMistake> mistakes;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Drop content-free triples so a degenerate payload can't render a header
    // over a lone ✕ icon (review #7).
    final items = mistakes.where((m) => m.mistake.isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 15)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.teachingWatchOutFor,
                style: AppTypography.label.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
          for (var i = 0; i < items.length; i++) ...[
            SizedBox(height: i == 0 ? AppSpacing.md : AppSpacing.lg),
            _MistakeRow(mistake: items[i]),
          ],
        ],
      ),
    );
  }
}

class _MistakeRow extends StatelessWidget {
  const _MistakeRow({required this.mistake});

  final CommonMistake mistake;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.close_rounded, size: 16, color: colors.onWarningContainer),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                mistake.mistake,
                style: AppTypography.bodySmall.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (mistake.whyTempting.isNotEmpty) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.lg),
            child: Text(
              'Tempting because: ${mistake.whyTempting}',
              style: AppTypography.caption.copyWith(color: colors.textMuted),
            ),
          ),
        ],
        if (mistake.fix.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Container(
            margin: const EdgeInsets.only(left: AppSpacing.lg),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.successContainer,
              borderRadius: AppRadius.smRadius,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_rounded,
                    size: 14, color: colors.onSuccessContainer),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    mistake.fix,
                    style: AppTypography.caption
                        .copyWith(color: colors.onSuccessContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 6. Key takeaway — the retrieval cue (gold accent)
// ---------------------------------------------------------------------------

class KeyTakeawayCard extends StatelessWidget {
  const KeyTakeawayCard({super.key, required this.takeaway});

  final KeyTakeaway takeaway;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      container: true,
      label: 'Key takeaway: ${takeaway.headline}'
          '${takeaway.detail == null ? "" : ". ${takeaway.detail}"}',
      excludeSemantics: true,
      child: Container(
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
            Row(
              children: [
                const Icon(Icons.lightbulb_rounded,
                    size: 16, color: AppColors.gold),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  context.l10n.teachingRememberThis,
                  style: AppTypography.label.copyWith(color: colors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              takeaway.headline,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (takeaway.detail != null && takeaway.detail!.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxs),
              Text(
                takeaway.detail!,
                style:
                    AppTypography.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 7. Practice ladder — easier / similar / harder (Pro)
// ---------------------------------------------------------------------------

class PracticeLadderCard extends StatelessWidget {
  const PracticeLadderCard({
    super.key,
    required this.ladder,
    this.onAttempt,
  });

  final PracticeLadder ladder;

  /// Attempt a rung (null → the rungs render read-only).
  final ValueChanged<PracticeItem>? onAttempt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fitness_center_rounded,
                  size: 16, color: AppColors.primaryAction),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.teachingYourTurn,
                style: AppTypography.label.copyWith(color: _emerald(context)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.l10n.teachingPracticeLadderIntro,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < ladder.rungs.length; i++) ...[
            _RungRow(item: ladder.rungs[i], onTap: onAttempt),
            if (i < ladder.rungs.length - 1)
              const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _RungRow extends StatelessWidget {
  const _RungRow({required this.item, required this.onTap});

  final PracticeItem item;
  final ValueChanged<PracticeItem>? onTap;

  // Theme-tuned container/on-container pairs (AA in both themes) — the raw accent
  // as both fill and text fell below AA, notably in dark mode (review #2).
  ({String label, Color fill, Color ink}) _rung(BuildContext context) {
    final colors = context.colors;
    return switch (item.rung) {
      'easier' => (
          label: context.l10n.teachingRungEasier,
          fill: colors.successContainer,
          ink: colors.onSuccessContainer
        ),
      'harder' => (
          label: context.l10n.teachingRungHarder,
          fill: colors.warningContainer,
          ink: colors.onWarningContainer
        ),
      _ => (
          label: context.l10n.teachingRungSimilar,
          fill: colors.infoContainer,
          ink: colors.onInfoContainer
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final r = _rung(context);
    final row = Container(
      constraints: const BoxConstraints(minHeight: 44), // a11y tap target
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: r.fill,
              borderRadius: AppRadius.pillRadius,
            ),
            child: Text(
              r.label,
              style: AppTypography.caption.copyWith(
                color: r.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: MathText(
              item.latex,
              style: AppTypography.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ),
          if (onTap != null)
            Icon(Icons.arrow_forward_rounded, size: 16, color: _emerald(context)),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: '${r.label} practice question',
      excludeSemantics: true,
      child: Pressable(
        onTap: () => onTap!(item),
        borderRadius: AppRadius.smRadius,
        child: row,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 8. Numi invite — the tutor hand-off
// ---------------------------------------------------------------------------

class NumiInviteStrip extends StatelessWidget {
  const NumiInviteStrip({super.key, required this.onAsk});

  /// Opens the tutor (null → the strip is hidden).
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    if (onAsk == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(
          text: context.l10n.teachingAskPrompt,
          avatarSize: 28,
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: context.l10n.teachingAskNumi,
          icon: Icons.forum_rounded,
          onPressed: onAsk,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 9. Approach — HONEST MODE: how to think about an unverifiable problem
// ---------------------------------------------------------------------------

class ApproachCard extends StatelessWidget {
  const ApproachCard({super.key, required this.approach});

  final List<String> approach;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final items = approach.where((s) => s.trim().isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🧭', style: TextStyle(fontSize: 15)),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.teachingHowToApproach,
                style: AppTypography.label.copyWith(color: _emerald(context)),
              ),
            ],
          ),
          for (var i = 0; i < items.length; i++) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: AppTypography.caption.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    items[i],
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.textPrimary, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// shared
// ---------------------------------------------------------------------------

class _TextLink extends StatelessWidget {
  const _TextLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44), // a11y tap target
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTypography.caption.copyWith(color: _emerald(context)),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_forward_rounded,
                  size: 14, color: _emerald(context)),
            ],
          ),
        ),
      ),
    );
  }
}
