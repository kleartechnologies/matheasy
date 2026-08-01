import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../core/animations/motion_aware_size.dart';
import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import '../../domain/teaching_models.dart';
import 'math_text.dart';
import 'step_diff.dart';

/// The emerald that highlights the changed span of a step, as the `#RRGGBB`
/// literal `\textcolor` needs. Derived from the ramp so it can't drift from the
/// brand: the changed span is *text*, so it takes the emerald that stays legible
/// on each theme's card ([AppColors.primary] itself is 2.97:1).
String changedSpanHex(BuildContext context) {
  final accent = context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
  return '#${(accent.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// The step-by-step spine — the map and the lesson in one widget.
///
/// Every step is on screen at once as a compact row (the expression going *in*,
/// plus one line naming what happens to it), so the learner can always see how
/// long the road is and where they are on it. Exactly one row is **focused**: it
/// lifts out of the list as a card showing `before → what we do → after`, with
/// the changed span lit up on both lines, while the rest of the list recedes.
///
/// That is the whole idea: context from the list, attention from the card.
/// Reading a step never costs you your place, and tapping any row jumps there —
/// forward, back, or straight to the end.
///
/// Fully controlled: the parent owns [focused] so the lesson summary, practice
/// and Numi can react to progress. Index [steps].length is the Solution row.
class StepSpine extends StatefulWidget {
  const StepSpine({
    super.key,
    required this.problemLatex,
    required this.steps,
    required this.answerLatex,
    required this.focused,
    required this.expanded,
    required this.onFocus,
    required this.onCollapse,
    required this.onNext,
    required this.onBack,
    this.glossary = const [],
  });

  /// The problem as scanned — the expression the first step acts on.
  final String problemLatex;

  final List<SolutionStep> steps;

  /// The verified final answer, shown on the closing Solution row.
  final String answerLatex;

  /// 0 … [steps].length, where the last index is the Solution row.
  final int focused;

  /// Whether the [focused] row is open. False shows the bare list — the state
  /// the ✕ on a card returns you to.
  final bool expanded;

  final ValueChanged<int> onFocus;
  final VoidCallback onCollapse;
  final VoidCallback onNext;
  final VoidCallback onBack;

  /// Terms from the teaching layer's glossary. Any that appear in a step's
  /// instruction become tappable — the definition comes to the learner instead
  /// of making them go hunting for it.
  final List<DefinedTerm> glossary;

  @override
  State<StepSpine> createState() => _StepSpineState();
}

class _StepSpineState extends State<StepSpine> {
  /// Rides on the focused card so advancing can bring it into view — the point
  /// of a spine is lost if Next scrolls the card off the bottom.
  final _focusKey = GlobalKey();

  @override
  void didUpdateWidget(StepSpine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focused != widget.focused ||
        (widget.expanded && !oldWidget.expanded)) {
      _revealFocused();
    }
  }

  void _revealFocused() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _focusKey.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        // Just under the top edge: the card, and a hint of what comes next.
        alignment: 0.15,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppDurations.medium,
        curve: AppCurves.standard,
      );
    });
  }

  /// The expression this step starts from: the problem itself for the first
  /// step, otherwise wherever the previous step left off.
  String _before(int i) =>
      i == 0 ? widget.problemLatex : widget.steps[i - 1].resultLatex;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final steps = widget.steps;
    if (steps.isEmpty) return const SizedBox.shrink();

    final solutionIndex = steps.length;
    final focused = widget.focused.clamp(0, solutionIndex);
    final onSolution = focused == solutionIndex;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.medium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SpineHeader(
          current: focused + 1,
          total: solutionIndex + 1,
          showHint: focused == 0,
        ),
        const SizedBox(height: AppSpacing.md),
        // The list is one calm surface; the focused card is the thing that
        // rises out of it.
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: AppRadius.cardRadius,
          ),
          clipBehavior: Clip.antiAlias,
          child: MotionAwareSize(
            duration: motion,
            curve: AppCurves.standard,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (var i = 0; i <= solutionIndex; i++) ...[
                  if (i > 0 &&
                      !(widget.expanded && (i == focused || i - 1 == focused)))
                    Divider(
                      height: 1,
                      indent: AppSpacing.lg,
                      endIndent: AppSpacing.lg,
                      color: colors.divider,
                    ),
                  if (widget.expanded && i == focused)
                    KeyedSubtree(
                      key: _focusKey,
                      child: i == solutionIndex
                          ? _SolutionCard(
                              answerLatex: widget.answerLatex,
                              onClose: widget.onCollapse,
                            )
                          : _FocusCard(
                              step: steps[i],
                              before: _before(i),
                              after: steps[i].resultLatex,
                              glossary: widget.glossary,
                              onClose: widget.onCollapse,
                              onNext: widget.onNext,
                            ),
                    )
                  else if (i == solutionIndex)
                    _SolutionRow(
                      answerLatex: widget.answerLatex,
                      onTap: () => widget.onFocus(i),
                    )
                  else
                    _SpineRow(
                      latex: _before(i),
                      label: steps[i].title,
                      onTap: () => widget.onFocus(i),
                    ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            if (focused > 0) ...[
              _RoundButton(
                icon: Icons.undo_rounded,
                label: context.l10n.solutionStepBack,
                onTap: widget.onBack,
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            // At the *open* Solution row there is nowhere left to go — the
            // summary below takes over rather than a button pretending there
            // is more. Shut, it still offers the way back in.
            if (!(onSolution && widget.expanded))
              Expanded(
                child: PrimaryButton(
                  label: context.l10n.resultNextStep,
                  onPressed: widget.onNext,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _SpineHeader extends StatelessWidget {
  const _SpineHeader({
    required this.current,
    required this.total,
    required this.showHint,
  });

  final int current;
  final int total;

  /// The "you can tap these" affordance — shown once, at the start, then it
  /// stops being news.
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.solutionSolvingSteps,
                style:
                    AppTypography.title.copyWith(color: colors.textPrimary),
              ),
            ),
            Semantics(
              label: context.l10n.solutionProgressSemantics(current, total),
              excludeSemantics: true,
              child: Text(
                context.l10n.resultStepOfTotal(current, total),
                style: AppTypography.caption.copyWith(
                  color: colors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (showHint)
          Text(
            context.l10n.solutionTapStepHint,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Collapsed rows
// ---------------------------------------------------------------------------

/// One step at rest: where the expression stands, and one line saying what
/// happens to it next. Quiet enough to scan, complete enough to orient by.
class _SpineRow extends StatelessWidget {
  const _SpineRow({required this.latex, required this.label, required this.onTap});

  final String latex;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AdaptiveMath(
                    latex,
                    minFontSize: 16,
                    maxFontSize: 22,
                    style: AppTypography.headingSmall
                        .copyWith(color: colors.textSecondary),
                  ),
                  if (label.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      label,
                      style: AppTypography.caption
                          .copyWith(color: colors.textMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 22, color: colors.textMuted),
          ],
        ),
      ),
    );
  }
}

/// The closing row — the verified answer, marked by an emerald rail so the eye
/// finds the end of the road without reading a word.
class _SolutionRow extends StatelessWidget {
  const _SolutionRow({required this.answerLatex, required this.onTap});

  final String answerLatex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Pressable(
      onTap: onTap,
      child: _Railed(
        color: AppColors.primaryAction,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.solutionAnswerRow,
              style: AppTypography.label.copyWith(
                color: context.isDark
                    ? AppColors.primaryLight
                    : AppColors.primaryDark,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AdaptiveMath(
              answerLatex,
              minFontSize: 20,
              maxFontSize: 28,
              style: AppTypography.displaySmall
                  .copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The focused step
// ---------------------------------------------------------------------------

/// The step, opened: what we start from, what we do, what we get — with the
/// part that actually moves lit up on both expressions.
class _FocusCard extends StatefulWidget {
  const _FocusCard({
    required this.step,
    required this.before,
    required this.after,
    required this.glossary,
    required this.onClose,
    required this.onNext,
  });

  final SolutionStep step;
  final String before;
  final String after;
  final List<DefinedTerm> glossary;
  final VoidCallback onClose;
  final VoidCallback onNext;

  @override
  State<_FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<_FocusCard> {
  /// The deeper layer — why the rule holds, and the trap here. One tap away,
  /// never in the way.
  bool _explained = false;

  bool get _hasDepth =>
      widget.step.detail.isNotEmpty ||
      (widget.step.explanation?.isNotEmpty ?? false) ||
      (widget.step.commonMistake?.isNotEmpty ?? false);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final step = widget.step;
    final hex = changedSpanHex(context);
    return _LiftedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Where we are — with the part about to change already glowing.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AdaptiveMath(
                  widget.before,
                  renderLatex: emphasizeOutgoing(widget.before, widget.after,
                      colorHex: hex),
                  minFontSize: 18,
                  maxFontSize: 28,
                  style: AppTypography.displaySmall
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _IconTap(
                icon: Icons.close_rounded,
                label: context.l10n.actionClose,
                onTap: widget.onClose,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // What we do about it, hung off an arrow so the eye follows the move.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ArrowRail(),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (step.pivotal &&
                          (step.selfExplainPrompt?.isNotEmpty ?? false)) ...[
                        _SelfExplainBox(prompt: step.selfExplainPrompt!),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      _TransitionText(
                        text: step.title,
                        rule: step.rule,
                        glossary: widget.glossary,
                      ),
                      if (_hasDepth) ...[
                        const SizedBox(height: AppSpacing.sm),
                        // Built only when asked for: the collapsed state is
                        // genuinely absent, not merely invisible.
                        if (_explained)
                          _StepDepth(step: step)
                        else
                          _ExplainHowPill(
                            onTap: () => setState(() => _explained = true),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // And what that leaves us with.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AdaptiveMath(
                  widget.after,
                  renderLatex: emphasizeChanged(widget.before, widget.after,
                      colorHex: hex),
                  minFontSize: 18,
                  maxFontSize: 28,
                  style: AppTypography.displaySmall.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _IconTap(
                icon: Icons.arrow_downward_rounded,
                label: context.l10n.resultNextStep,
                onTap: widget.onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The Solution row, opened — the end of the road, nothing more to unfold.
class _SolutionCard extends StatelessWidget {
  const _SolutionCard({required this.answerLatex, required this.onClose});

  final String answerLatex;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return _LiftedCard(
      railColor: AppColors.primaryAction,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.solutionAnswerRow,
                  style: AppTypography.label.copyWith(
                    color: context.isDark
                        ? AppColors.primaryLight
                        : AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                AdaptiveMath(
                  answerLatex,
                  minFontSize: 22,
                  maxFontSize: 32,
                  style: AppTypography.displaySmall.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          _IconTap(
            icon: Icons.close_rounded,
            label: context.l10n.actionClose,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

/// The white card that rises out of the muted list — full-bleed, so the focused
/// step reads as a layer above the spine rather than another item in it.
class _LiftedCard extends StatelessWidget {
  const _LiftedCard({required this.child, this.railColor});

  final Widget child;
  final Color? railColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: context.isDark ? 0.4 : 0.09),
            blurRadius: 22,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: _Railed(
        color: railColor,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: child,
      ),
    );
  }
}

/// Content with an optional full-height accent rail down its left edge.
///
/// The rail is *positioned*, not a Row sibling: these cards hold [AdaptiveMath],
/// which measures itself with a `LayoutBuilder`, and a LayoutBuilder cannot
/// answer the intrinsic-height query an `IntrinsicHeight` row would make.
class _Railed extends StatelessWidget {
  const _Railed({
    required this.child,
    required this.padding,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  static const double _railWidth = 4;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: color == null
              ? padding
              : padding.copyWith(left: padding.left + _railWidth),
          child: child,
        ),
        if (color != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: _railWidth,
            child: ColoredBox(color: color!),
          ),
      ],
    );
  }
}

/// The line-and-arrowhead that carries the eye from the before expression to
/// the after one.
class _ArrowRail extends StatelessWidget {
  const _ArrowRail();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 14,
      child: Column(
        children: [
          Expanded(child: Container(width: 1.5, color: colors.border)),
          Icon(Icons.arrow_downward_rounded, size: 14, color: colors.textMuted),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The instruction, with its glossary terms live
// ---------------------------------------------------------------------------

/// The step's instruction. Any glossary term inside it becomes a tappable,
/// underlined emerald span — the definition arrives where the confusion is,
/// instead of sending the learner off to find it.
class _TransitionText extends StatefulWidget {
  const _TransitionText({
    required this.text,
    required this.rule,
    required this.glossary,
  });

  final String text;

  /// The named property behind the move, e.g. "Distributive property".
  final String? rule;

  final List<DefinedTerm> glossary;

  @override
  State<_TransitionText> createState() => _TransitionTextState();
}

class _TransitionTextState extends State<_TransitionText> {
  late final List<_Fragment> _fragments;
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _fragments = _linkTerms(widget.text, widget.glossary);
    for (final f in _fragments) {
      if (f.term == null) continue;
      final term = f.term!;
      _recognizers.add(
        TapGestureRecognizer()..onTap = () => _defineTerm(term),
      );
    }
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  void _defineTerm(DefinedTerm term) => AppBottomSheet.show(
        context,
        title: term.term,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          child: Text(
            term.plain,
            style: AppTypography.bodyMedium.copyWith(
              color: context.colors.textSecondary,
              height: 1.5,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final base = AppTypography.bodyMedium
        .copyWith(color: colors.textPrimary, height: 1.45);

    final linked = _fragments.any((f) => f.term != null);
    var linkIndex = 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No glossary hit — stay a plain Text so the instruction is selectable,
        // readable by every tool, and free of span machinery it doesn't need.
        if (widget.text.isNotEmpty && !linked)
          Text(widget.text, style: base)
        else if (widget.text.isNotEmpty)
          RichText(
            text: TextSpan(
              style: base,
              children: [
                for (final f in _fragments)
                  if (f.term == null)
                    TextSpan(text: f.text)
                  else
                    TextSpan(
                      text: f.text,
                      style: base.copyWith(
                        color: emerald,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: emerald,
                      ),
                      recognizer: _recognizers[linkIndex++],
                    ),
              ],
            ),
          ),
        if (widget.rule != null && widget.rule!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: AppRadius.smRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.straighten_rounded,
                    size: 13, color: colors.onPrimaryContainer),
                const SizedBox(width: AppSpacing.xxs),
                Flexible(
                  child: Text(
                    widget.rule!,
                    style: AppTypography.caption.copyWith(
                      color: colors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
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

/// A run of the instruction: plain prose, or a glossary term to link.
class _Fragment {
  const _Fragment(this.text, [this.term]);

  final String text;
  final DefinedTerm? term;
}

bool _isWordChar(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || (u >= 48 && u <= 57);
}

/// Splits [text] so that the FIRST whole-word occurrence of each glossary term
/// becomes its own fragment. First occurrence only — a paragraph where every
/// other word is a link teaches nobody anything.
List<_Fragment> _linkTerms(String text, List<DefinedTerm> glossary) {
  if (text.isEmpty || glossary.isEmpty) return [_Fragment(text)];
  final terms = [
    for (final t in glossary)
      if (t.term.trim().length >= 3 && t.plain.trim().isNotEmpty) t,
  ]..sort((a, b) => b.term.length.compareTo(a.term.length));
  if (terms.isEmpty) return [_Fragment(text)];

  final lower = text.toLowerCase();
  final used = <String>{};
  final out = <_Fragment>[];
  final buffer = StringBuffer();
  var i = 0;

  while (i < text.length) {
    DefinedTerm? hit;
    for (final t in terms) {
      final needle = t.term.toLowerCase();
      if (used.contains(needle)) continue;
      if (!lower.startsWith(needle, i)) continue;
      // Whole words only, so "sum" never lights up inside "assumption".
      final before = i == 0 ? '' : text[i - 1];
      final afterAt = i + needle.length;
      final after = afterAt >= text.length ? '' : text[afterAt];
      if (before.isNotEmpty && _isWordChar(before)) continue;
      if (after.isNotEmpty && _isWordChar(after)) continue;
      hit = t;
      break; // terms are longest-first, so the first match is the best one
    }
    if (hit == null) {
      buffer.write(text[i]);
      i++;
      continue;
    }
    if (buffer.isNotEmpty) {
      out.add(_Fragment(buffer.toString()));
      buffer.clear();
    }
    out.add(_Fragment(text.substring(i, i + hit.term.length), hit));
    used.add(hit.term.toLowerCase());
    i += hit.term.length;
  }
  if (buffer.isNotEmpty) out.add(_Fragment(buffer.toString()));
  return out;
}

// ---------------------------------------------------------------------------
// Depth
// ---------------------------------------------------------------------------

/// The invitation into the reasoning — offered, never forced.
class _ExplainHowPill extends StatelessWidget {
  const _ExplainHowPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: context.l10n.solutionExplainHow,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: AppRadius.pillRadius,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.solutionExplainHow,
                style: AppTypography.caption.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_rounded,
                  size: 14, color: colors.onPrimaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the move is legal, and the trap students fall into right here.
class _StepDepth extends StatelessWidget {
  const _StepDepth({required this.step});

  final SolutionStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final explanation = step.explanation;
    final mistake = step.commonMistake;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step.detail.isNotEmpty) ...[
          Text(
            context.l10n.solutionWhyThisWorks,
            style: AppTypography.label.copyWith(color: emerald),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            step.detail,
            style: AppTypography.bodySmall
                .copyWith(color: colors.textSecondary, height: 1.45),
          ),
        ],
        if (explanation != null && explanation.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            explanation,
            style: AppTypography.caption.copyWith(color: colors.textSecondary),
          ),
        ],
        if (mistake != null && mistake.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.warningContainer,
              borderRadius: AppRadius.smRadius,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 14, color: colors.onWarningContainer),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    mistake,
                    style: AppTypography.caption
                        .copyWith(color: colors.onWarningContainer),
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

/// The pivotal-step "your turn" prompt — a QUESTION shown before the reasoning.
class _SelfExplainBox extends StatelessWidget {
  const _SelfExplainBox({required this.prompt});

  final String prompt;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.smRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.edit_rounded, size: 15, color: emerald),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTypography.bodySmall
                    .copyWith(color: colors.onPrimaryContainer),
                children: [
                  TextSpan(
                    text: context.l10n.solutionYourTurn,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: prompt),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// A quiet circular control — present, tappable at 48dp, subordinate to Next.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colors.surface,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, size: 20, color: colors.textSecondary),
        ),
      ),
    );
  }
}

/// The small in-card taps (close, advance) — 40dp of target around a 20dp icon.
class _IconTap extends StatelessWidget {
  const _IconTap({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 22, color: colors.textSecondary),
        ),
      ),
    );
  }
}
