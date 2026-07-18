import 'package:flutter/material.dart';

import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/localization/l10n_extension.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_durations.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/visual_models.dart';
import '../math_text.dart';
import 'concept_painter.dart';

/// Building blocks shared by the Visual Learning renderers (Tiers 1–3):
/// the interactive step card, the operation chip, the key-ideas takeaway,
/// the method card and the "Ask Matheasy" affordance.

/// The operation applied in a step, e.g. `− 5` — same visual language as the
/// Solution tab's chip so the two tabs feel related.
class VisualOperationChip extends StatelessWidget {
  const VisualOperationChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(color: colors.onWarningContainer),
      ),
    );
  }
}

/// One expandable learning card (Tier 2/3): the transformation is always
/// visible; tapping reveals the "why", a revealable hint, and Ask Matheasy.
class VisualStepCard extends StatefulWidget {
  const VisualStepCard({
    super.key,
    required this.step,
    required this.number,
    required this.onAskMatheasy,
    this.defaultExpanded = false,
  });

  final VisualStep step;
  final int number;
  final VoidCallback onAskMatheasy;
  final bool defaultExpanded;

  @override
  State<VisualStepCard> createState() => _VisualStepCardState();
}

class _VisualStepCardState extends State<VisualStepCard> {
  late bool _expanded = widget.defaultExpanded;
  bool _hintRevealed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final step = widget.step;
    // Emerald content on a card — per-theme legible tone, not the logo tile.
    final emeraldLabel =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.number}',
                    style: AppTypography.caption.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    step.title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (step.operationLabel != null)
                  VisualOperationChip(label: step.operationLabel!),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AdaptiveMath(
              step.beforeLatex,
              minFontSize: 22,
              maxFontSize: 28,
              style: AppTypography.bodyLarge
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Icon(
              Icons.arrow_downward_rounded,
              size: 16,
              color: emeraldLabel,
            ),
            const SizedBox(height: AppSpacing.xs),
            AdaptiveMath(
              step.afterLatex,
              minFontSize: 26,
              maxFontSize: 34,
              style: AppTypography.headingSmall
                  .copyWith(color: colors.textPrimary),
            ),
            AnimatedCrossFade(
              duration: AppDurations.fast,
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.explanation,
                      style: AppTypography.bodySmall
                          .copyWith(color: colors.textSecondary),
                    ),
                    if (step.hint != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _HintReveal(
                        hint: step.hint!,
                        revealed: _hintRevealed,
                        onReveal: () => setState(() => _hintRevealed = true),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    AskMatheasyButton(onPressed: widget.onAskMatheasy),
                  ],
                ),
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  _expanded
                      ? context.l10n.solutionHideWhy
                      : context.l10n.visualTapToLearn,
                  style: AppTypography.caption.copyWith(color: emeraldLabel),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: AppDurations.fast,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: emeraldLabel,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A hint kept behind a tap so students try first — the reveal is the
/// interaction, so it needs its own affordance and semantics.
class _HintReveal extends StatelessWidget {
  const _HintReveal({
    required this.hint,
    required this.revealed,
    required this.onReveal,
  });

  final VisualHint hint;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (!revealed) {
      return Semantics(
        button: true,
        label: context.l10n.visualShowHint,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onReveal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lightbulb_outline_rounded,
                    size: 16, color: colors.onWarningContainer),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  context.l10n.visualShowHint,
                  style: AppTypography.caption
                      .copyWith(color: colors.onWarningContainer),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        hint.text,
        style:
            AppTypography.bodySmall.copyWith(color: colors.onWarningContainer),
      ),
    );
  }
}

/// The concept takeaway after the steps — what the student should remember.
class VisualKeyIdeasCard extends StatelessWidget {
  const VisualKeyIdeasCard({super.key, required this.explanation});

  final VisualExplanation explanation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      color: colors.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded,
                  size: 16, color: colors.onPrimaryContainer),
              const SizedBox(width: AppSpacing.xs),
              Text(
                context.l10n.visualKeyIdeas,
                style: AppTypography.label
                    .copyWith(color: colors.onPrimaryContainer),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            explanation.summary,
            style: AppTypography.bodyMedium
                .copyWith(color: colors.onPrimaryContainer),
          ),
          for (final idea in explanation.keyIdeas) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '•  ',
                  style: AppTypography.bodySmall
                      .copyWith(color: colors.onPrimaryContainer),
                ),
                Expanded(
                  child: Text(
                    idea,
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.onPrimaryContainer),
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

/// The named strategy behind the walkthrough (e.g. "Balance method").
class VisualMethodCard extends StatelessWidget {
  const VisualMethodCard({super.key, required this.method});

  final VisualMethod method;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.route_rounded,
              size: 20,
              color: context.isDark
                  ? AppColors.primaryLight
                  : AppColors.primaryDark),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method.name,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  method.description,
                  style: AppTypography.bodySmall
                      .copyWith(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bridge between Visual Learning and Matheasy — asks the tutor about the
/// step currently on screen, with that step's context attached.
class AskMatheasyButton extends StatelessWidget {
  const AskMatheasyButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GhostButton(
      label: context.l10n.visualAskAboutStep,
      icon: Icons.chat_bubble_outline_rounded,
      expand: true,
      onPressed: onPressed,
    );
  }
}

/// Renders a [VisualConcept] — the AI's drawable metadata. A drawable kind
/// paints on an explorable (pinch-zoom/pan) canvas; the [VisualConceptKind.generic]
/// fallback shows the caption as a concept card. Shared by all three tiers so
/// a unit circle on a Tier 2 trig solution or a parabola on a Tier 1 quadratic
/// is never silently discarded.
class VisualConceptView extends StatelessWidget {
  const VisualConceptView({super.key, required this.concept});

  final VisualConcept concept;

  @override
  Widget build(BuildContext context) {
    if (concept.kind == VisualConceptKind.generic) {
      return _ConceptCaptionCard(concept: concept);
    }
    return _ConceptCanvas(concept: concept);
  }
}

/// The explorable drawing: pinch-to-zoom and pan via [InteractiveViewer], with
/// the caption as both the visible legend and the accessible description. The
/// [RepaintBoundary] isolates the painter so a pan/zoom gesture doesn't repaint
/// the surrounding tab, and the tab doesn't repaint the canvas.
class _ConceptCanvas extends StatelessWidget {
  const _ConceptCanvas({required this.concept});

  final VisualConcept concept;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The drawn concept is non-text graphics on a card: it needs the emerald
    // that clears 3:1 on this theme's surface, which the logo tone does not.
    final stroke =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final palette = ConceptPalette(
      grid: colors.divider,
      axis: colors.textMuted,
      stroke: stroke,
      fill: stroke.withValues(alpha: 0.16),
      accent: AppColors.warning,
      textColor: colors.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: EdgeInsets.zero,
          clip: true,
          child: AspectRatio(
            aspectRatio: 3 / 2,
            child: Semantics(
              image: true,
              label: concept.caption,
              child: ExcludeSemantics(
                child: InteractiveViewer(
                  maxScale: 4,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: ConceptPainter(
                        concept: concept,
                        palette: palette,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.pinch_rounded, size: 14, color: colors.textMuted),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                concept.caption,
                style:
                    AppTypography.caption.copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
        if (concept.labels.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              for (final label in concept.labels.values)
                FeatureChip(label: label),
            ],
          ),
        ],
      ],
    );
  }
}

/// Fallback when the concept has no drawable form — the caption still delivers
/// the conceptual takeaway as a card.
class _ConceptCaptionCard extends StatelessWidget {
  const _ConceptCaptionCard({required this.concept});

  final VisualConcept concept;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.psychology_rounded,
            size: 20,
            color:
                context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              concept.caption,
              style:
                  AppTypography.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
