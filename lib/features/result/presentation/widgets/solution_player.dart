import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/animation_schema.dart';
import '../../domain/result_models.dart';
import 'math_text.dart';

/// One step to play. The expression + sentence come from the VERIFIED solve
/// (`ResultData.steps`), so this exists for EVERY problem type; the token chips
/// are overlaid from the server `animationSchema` only where it's available.
@immutable
class PlayerStep {
  const PlayerStep({
    required this.latex,
    required this.explanation,
    this.tokens = const [],
  });

  /// The expression to display for this step, as LaTeX.
  final String latex;

  /// The tutor "why" sentence for this step (already resolved; may be empty).
  final String explanation;

  /// Static, colour-coded token chips (empty unless the rich schema covered this
  /// step). PHASE 1 renders these as chips only — no on-expression motion.
  final List<TokenMapping> tokens;
}

/// Build the play-through steps for ANY verified solve.
///
/// Drives the expression + tutor sentence from `result.steps` (present for every
/// problem type — linear, quadratic, arithmetic, calculus, systems, …), and
/// overlays the server `animationSchema`'s token chips by matching step index
/// where present. No math is computed here: it only re-presents already-verified
/// values (golden rule). Steps with no expression are skipped.
List<PlayerStep> buildPlayerSteps(ResultData result) {
  final schema = result.animationSchema;
  final tokensByIndex = <int, List<TokenMapping>>{
    if (schema != null)
      for (final inst in schema.steps) inst.stepIndex: inst.tokens,
  };
  final out = <PlayerStep>[];
  final steps = result.steps;
  for (var i = 0; i < steps.length; i++) {
    final latex = steps[i].resultLatex.trim();
    if (latex.isEmpty) continue;
    out.add(PlayerStep(
      latex: latex,
      explanation: _stepSentence(steps[i]),
      tokens: tokensByIndex[i] ?? const [],
    ));
  }
  return out;
}

/// The sentence under the math: the tutor "why", else the operation label, else
/// nothing. Never a raw key (there is none on this universal path).
String _stepSentence(SolutionStep s) {
  if (s.detail.trim().isNotEmpty) return s.detail.trim();
  if (s.title.trim().isNotEmpty) return s.title.trim();
  return '';
}

/// PHASE 1 — the STATIC "Play Solution" player, rendered INLINE (the Pro Visual
/// Learning tab's content). It steps through the verified solution one step at a
/// time: the step's expression (large), its participating tokens as static
/// coloured chips (where the schema provides them), and the tutor "why" sentence.
///
/// DELIBERATELY NOT ANIMATED (a later phase). No tweens, no auto-play, no
/// fade-in, no hand-drawn circles, no token motion across the equals sign. The
/// `// ANIMATION PHASE:` comments mark exactly where each of those hooks in.
class SolutionPlayer extends StatefulWidget {
  const SolutionPlayer({super.key, required this.steps, this.onAskStep});

  final List<PlayerStep> steps;

  /// Optional — "Ask Matheasy about this step" (the current step index). Null
  /// hides the affordance (e.g. in a bare preview).
  final ValueChanged<int>? onAskStep;

  @override
  State<SolutionPlayer> createState() => _SolutionPlayerState();
}

class _SolutionPlayerState extends State<SolutionPlayer> {
  int _index = 0;

  int get _lastIndex => widget.steps.length - 1;
  bool get _isLast => _index == _lastIndex;

  void _go(int index) => setState(() => _index = index.clamp(0, _lastIndex));

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final step = steps[_index.clamp(0, _lastIndex)];

    return Column(
      // Rendered inside a scrollable tab, so it takes its intrinsic height.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          index: _index,
          total: steps.length,
          isLast: _isLast,
          onAsk: widget.onAskStep == null
              ? null
              : () => widget.onAskStep!(_index),
        ),
        const SizedBox(height: AppSpacing.lg),
        // The current step's expression. ANIMATION PHASE: this is where the
        // step-to-step morph + per-token motion will play; this phase renders it
        // statically.
        _StepMath(latex: step.latex),
        // ANIMATION PHASE: per-token highlighting is drawn ON the expression above
        // (flutter_math renders LaTeX as an opaque block, so that needs LaTeX-span
        // mapping / an overlay). For now the participating tokens are surfaced as
        // static coloured chips so the data is visible.
        if (step.tokens.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _TokenChips(tokens: step.tokens),
        ],
        if (step.explanation.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          _StepExplanation(text: step.explanation),
        ],
        const SizedBox(height: AppSpacing.lg),
        _Progress(count: steps.length, current: _index),
        const SizedBox(height: AppSpacing.lg),
        _Controls(
          index: _index,
          isLast: _isLast,
          onPrev: () => _go(_index - 1),
          onNext: () => _go(_index + 1),
          onReplay: () => _go(0),
        ),
      ],
    );
  }
}

/// The "STEP x OF n" (or "SOLVED") label + an optional "Ask Matheasy" button.
class _Header extends StatelessWidget {
  const _Header({
    required this.index,
    required this.total,
    required this.isLast,
    required this.onAsk,
  });

  final int index;
  final int total;
  final bool isLast;
  final VoidCallback? onAsk;

  @override
  Widget build(BuildContext context) {
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Row(
      children: [
        Text(
          isLast
              ? context.l10n.resultSolved
              : context.l10n.resultStepOfUpper(index + 1, total),
          style: AppTypography.label.copyWith(color: emerald),
        ),
        const Spacer(),
        if (onAsk != null)
          Semantics(
            button: true,
            label: context.l10n.tutorAsk,
            excludeSemantics: true,
            child: Pressable(
              onTap: onAsk!,
              borderRadius: AppRadius.pillRadius,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.help_outline_rounded, size: 16, color: emerald),
                  const SizedBox(width: AppSpacing.xxs),
                  Text(
                    context.l10n.tutorAsk,
                    style: AppTypography.caption.copyWith(color: emerald),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The current step's expression, sized to the app's prominent-math band.
class _StepMath extends StatelessWidget {
  const _StepMath({required this.latex});

  final String latex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      // A tall box so the equation is the visual focus and never squeezed. Less
      // horizontal padding gives a wide expression more room before it scales.
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xxl,
      ),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.lgRadius,
      ),
      // AdaptiveMath fits the width (scaling down to minFontSize, then a final
      // BoxFit.scaleDown), so a long expression never overflows sideways; the tab
      // scrolls if a step is tall.
      child: AdaptiveMath(
        latex,
        // Key by the string so switching steps re-lays-out cleanly (no tween —
        // ANIMATION PHASE will swap this for an AnimatedSwitcher / morph).
        key: ValueKey(latex),
        // The app's prominent-math band — aligned with the final-answer hero
        // (min34/max56 in result_header), a touch smaller so the FINAL answer
        // stays the biggest math in the app while each step reads comfortably.
        minFontSize: 32,
        maxFontSize: 52,
        alignment: Alignment.center,
        style: AppTypography.displayMedium
            .copyWith(color: colors.onPrimaryContainer),
      ),
    );
  }
}

/// The step's participating tokens as static, colour-coded chips. STATIC COLOUR
/// ONLY — no highlight marks (circle/underline/box) and no motion this phase.
class _TokenChips extends StatelessWidget {
  const _TokenChips({required this.tokens});

  final List<TokenMapping> tokens;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final t in tokens)
          if (t.value.isNotEmpty) _TokenChip(token: t),
      ],
    );
  }
}

class _TokenChip extends StatelessWidget {
  const _TokenChip({required this.token});

  final TokenMapping token;

  @override
  Widget build(BuildContext context) {
    final color = _tokenColor(context, token.color);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smRadius,
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: MathText(
        token.value,
        style: AppTypography.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Maps a schema [TokenColor] to a legible, theme-aware colour. These are
/// FUNCTIONAL (data-viz) colours for the animation token palette, not brand art,
/// so they sit outside the emerald identity split on purpose.
Color _tokenColor(BuildContext context, TokenColor c) {
  final dark = context.isDark;
  switch (c) {
    case TokenColor.green:
      return dark ? AppColors.primaryLight : AppColors.primaryDark;
    case TokenColor.blue:
      return dark ? const Color(0xFF7FB6E8) : AppColors.info;
    case TokenColor.pink:
      return dark ? const Color(0xFFF48FB1) : const Color(0xFFB0246A);
  }
}

/// The step's tutor "why" line — a muted supporting line with a notes icon.
class _StepExplanation extends StatelessWidget {
  const _StepExplanation({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.notes_rounded, size: 16, color: colors.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style:
                  AppTypography.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The segmented step progress bar (one segment per step, filled up to current).
class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    // A non-text graphic → the tone that clears 3:1, never the 2.97:1 logo tone.
    final fill = context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: i <= current ? fill : context.colors.surfaceMuted,
                borderRadius: AppRadius.pillRadius,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Prev + a primary pill: "Next step" while stepping, "Play walkthrough" (replay
/// from the start) on the last step. No auto-play.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.index,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onReplay,
  });

  final int index;
  final bool isLast;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (index > 0) ...[
          _CircleButton(
            icon: Icons.arrow_back_rounded,
            semanticLabel: context.l10n.resultPreviousStep,
            onTap: onPrev,
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: _PrimaryPill(
            label: isLast
                ? context.l10n.resultPlayWalkthroughShort
                : context.l10n.resultNextStep,
            icon: isLast ? Icons.replay_rounded : Icons.arrow_forward_rounded,
            onTap: isLast ? onReplay : onNext,
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 22, color: colors.textSecondary),
        ),
      ),
    );
  }
}

class _PrimaryPill extends StatelessWidget {
  const _PrimaryPill({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      borderRadius: AppRadius.pillRadius,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          // Solid: the label is white (primaryAction is 4.78:1).
          color: AppColors.primaryAction,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: AppTypography.button
                  .copyWith(color: AppColors.white, fontSize: 15),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(icon, size: 20, color: AppColors.white),
          ],
        ),
      ),
    );
  }
}
