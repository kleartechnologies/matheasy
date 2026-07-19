import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/animation_schema.dart';
import 'math_text.dart';

/// PHASE 1 — the STATIC renderer of the server `animationSchema`.
///
/// It shows one step at a time (the step's `afterLatex`), a "STEP x OF n"
/// indicator + progress bar, Prev/Next controls, and the step's tutor "why"
/// sentence. That sentence is NOT generated here — it is the narration the solver
/// already wrote for each step (`ResultData.steps[].detail`), passed in as
/// [stepDetails] and looked up by the instruction's `stepIndex`. The participating
/// tokens are listed as static coloured chips below the math.
///
/// DELIBERATELY NOT ANIMATED (a later phase). There are NO tweens, no auto-play,
/// no fade-in, no hand-drawn circles, and no token motion across the equals sign.
/// The `// ANIMATION PHASE:` comments mark exactly where each of those hooks in.
class SolutionPlayer extends StatefulWidget {
  const SolutionPlayer({
    super.key,
    required this.schema,
    this.stepDetails = const [],
    this.stepLabels = const [],
  });

  final AnimationSchema schema;

  /// The per-step tutor "why" sentences (from `ResultData.steps[].detail`),
  /// indexed to match the exam-pick method's steps. Looked up by each
  /// instruction's `stepIndex`. Narrow by design (a plain list, not the whole
  /// result) so the player stays testable. Empty ⇒ every step falls back.
  final List<String> stepDetails;

  /// The per-step operation labels (from `ResultData.steps[].title`, e.g.
  /// "Divide both sides") — the always-present fallback when a `why` sentence is
  /// missing for a step. Parallel to [stepDetails].
  final List<String> stepLabels;

  /// Presents the player as a blurred modal — mirrors `PlaySolutionOverlay.show`.
  static Future<void> show(
    BuildContext context, {
    required AnimationSchema schema,
    List<String> stepDetails = const [],
    List<String> stepLabels = const [],
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.l10n.resultPlaySolution,
      barrierColor: context.colors.scrim,
      transitionDuration: AppDurations.medium,
      pageBuilder: (_, _, _) => SolutionPlayer(
        schema: schema,
        stepDetails: stepDetails,
        stepLabels: stepLabels,
      ),
      transitionBuilder: (context, animation, _, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: AppCurves.emphasized);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<SolutionPlayer> createState() => _SolutionPlayerState();
}

class _SolutionPlayerState extends State<SolutionPlayer> {
  int _index = 0;

  int get _lastIndex => widget.schema.length - 1;
  bool get _isLast => _index == _lastIndex;

  void _go(int index) => setState(() => _index = index.clamp(0, _lastIndex));

  /// The sentence shown under the math, resolved DEFENSIVELY so the raw
  /// `explanationKey` can never reach the user. `stepIndex` is the original
  /// mathsteps array index while [SolutionPlayer.stepDetails]/[stepLabels] use the
  /// compacted (post-filter) index — they coincide today only because no equation
  /// step lacks an equation, so we never rely on that: any miss degrades to a
  /// humanized label, never to code and never to a crash.
  String _explanationFor(AnimationInstruction step) {
    final i = step.stepIndex;
    // 1) The tutor "why" sentence already narrated for this step.
    if (i >= 0 &&
        i < widget.stepDetails.length &&
        widget.stepDetails[i].trim().isNotEmpty) {
      return widget.stepDetails[i].trim();
    }
    // 2) The always-present operation label for this step, if in range.
    if (i >= 0 &&
        i < widget.stepLabels.length &&
        widget.stepLabels[i].trim().isNotEmpty) {
      return widget.stepLabels[i].trim();
    }
    // 3) Last resort: a humanized changeType — NEVER the raw "anim.step.X" key.
    return _humanizeChangeType(step.changeType);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final steps = widget.schema.steps;
    // Guarded by the caller (only shown for a non-empty schema), but stay safe.
    if (steps.isEmpty) return const SizedBox.shrink();
    final step = steps[_index.clamp(0, _lastIndex)];

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadius.modalRadius,
                  boxShadow: context.elevation.floating,
                ),
                // Not in a ListView — bound it to the screen so enlarged math /
                // scaled text scrolls vertically instead of overflowing.
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Header(
                        index: _index,
                        total: steps.length,
                        isLast: _isLast,
                        onClose: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // The current step's arrived-at expression. ANIMATION PHASE:
                      // this is where `beforeLatex → afterLatex` will morph and the
                      // per-token motion (move_across_equals, combine_terms, …) will
                      // play; this phase just renders the after-state statically.
                      _StepMath(latex: step.afterLatex),
                      // ANIMATION PHASE: per-token highlighting is drawn ON the
                      // expression above (flutter_math renders LaTeX as an opaque
                      // block, so that needs LaTeX-span mapping / an overlay — not
                      // this phase). For now the participating tokens are surfaced
                      // as static coloured chips so the data is visible + verifiable.
                      if (step.tokens.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        _TokenChips(tokens: step.tokens),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      // The tutor "why" for this step — the narration the solver
                      // already wrote (`stepDetails`), resolved defensively so the
                      // raw explanationKey never surfaces.
                      _StepExplanation(text: _explanationFor(step)),
                      const SizedBox(height: AppSpacing.lg),
                      _Progress(count: steps.length, current: _index),
                      const SizedBox(height: AppSpacing.lg),
                      _Controls(
                        index: _index,
                        isLast: _isLast,
                        onPrev: () => _go(_index - 1),
                        onNext: () => _go(_index + 1),
                        onDone: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "STEP x OF n" (or "SOLVED") label + a close button.
class _Header extends StatelessWidget {
  const _Header({
    required this.index,
    required this.total,
    required this.isLast,
    required this.onClose,
  });

  final int index;
  final int total;
  final bool isLast;
  final VoidCallback onClose;

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
        _CircleButton(
          icon: Icons.close_rounded,
          semanticLabel: context.l10n.resultCloseWalkthrough,
          onTap: onClose,
        ),
      ],
    );
  }
}

/// The current step's arrived-at expression, sized to fit.
class _StepMath extends StatelessWidget {
  const _StepMath({required this.latex});

  final String latex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      // A tall box (generous vertical padding) so the equation is the visual
      // focus and never squeezed against the controls below. Slightly less
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
      // BoxFit.scaleDown), so a long expression never overflows sideways; a tall
      // one scrolls with the enclosing SingleChildScrollView.
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

/// Readable labels for the common mathsteps changeTypes — the LAST-RESORT
/// fallback (`_explanationFor` tier 3) so the raw "anim.step.X" key can never
/// reach the user. Mirrors the server's operation labels for the equation family;
/// anything else degrades to a generic Title Case of the code.
const Map<String, String> _changeTypeLabels = {
  'ADD_TO_BOTH_SIDES': 'Add to both sides',
  'SUBTRACT_FROM_BOTH_SIDES': 'Subtract from both sides',
  'MULTIPLY_TO_BOTH_SIDES': 'Multiply both sides',
  'MULTIPLY_BOTH_SIDES_BY_INVERSE_FRACTION': 'Multiply both sides',
  'MULTIPLY_BOTH_SIDES_BY_NEGATIVE_ONE': 'Multiply both sides',
  'DIVIDE_FROM_BOTH_SIDES': 'Divide both sides',
  'SIMPLIFY_LEFT_SIDE': 'Simplify',
  'SIMPLIFY_RIGHT_SIDE': 'Simplify',
  'SIMPLIFY_ARITHMETIC': 'Simplify',
  'SIMPLIFY_FRACTION': 'Simplify the fraction',
  'COLLECT_AND_COMBINE_LIKE_TERMS': 'Combine like terms',
  'ADD_POLYNOMIAL_TERMS': 'Combine like terms',
};

/// A readable label for a changeType. Never returns the raw key: a mapped label,
/// else a Title-Cased humanization of the code, else "Step".
String _humanizeChangeType(String code) {
  final mapped = _changeTypeLabels[code];
  if (mapped != null) return mapped;
  final words = code.toLowerCase().replaceAll('_', ' ').trim();
  if (words.isEmpty) return 'Step';
  return '${words[0].toUpperCase()}${words.substring(1)}';
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

/// The step's tutor "why" line — the sentence resolved by `_explanationFor`
/// (already non-empty; the raw explanationKey never reaches here). Same muted line
/// with the notes icon the placeholder used — only the text SOURCE changed.
class _StepExplanation extends StatelessWidget {
  const _StepExplanation({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
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
              style: AppTypography.bodySmall.copyWith(
                color: colors.textSecondary,
              ),
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

/// Prev / Next (→ "Got it" on the last step). No auto-play.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.index,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onDone,
  });

  final int index;
  final bool isLast;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onDone;

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
            label:
                isLast ? context.l10n.resultGotIt : context.l10n.resultNextStep,
            icon: isLast
                ? Icons.check_circle_rounded
                : Icons.arrow_forward_rounded,
            onTap: isLast ? onDone : onNext,
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
