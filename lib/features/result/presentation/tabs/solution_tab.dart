import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
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
import '../widgets/math_text.dart';
import '../widgets/result_graph.dart';
import '../widgets/step_diff.dart';
import '../widgets/teaching/teaching_cards.dart';

/// Diameter of the numbered rail bullets; trailing content indents past it.
const double _railWidth = 30;
const double _railIndent = _railWidth + AppSpacing.md;

/// The emerald that highlights the changed span of a step (§5), as the
/// `#RRGGBB` literal `\textcolor` needs. Derived from the ramp so it cannot
/// drift from the brand: the changed span is *text*, so it takes the emerald
/// that stays legible as a label on each theme's card ([AppColors.primary]
/// itself is 2.97:1 and would disappear).
String _accentHex(BuildContext context) {
  final accent = context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
  return '#${(accent.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// Tab 1 — the step-by-step worked solution (spec §4/§5).
///
/// The stepper reveals ONE step at a time by default ("Next step"), with a
/// "Reveal all" toggle, and — when there is more than one method — a switcher so
/// each method drives its own stepper (the exam pick is badged). Every step past
/// the first highlights WHAT CHANGED from the previous step (accent colour, plus
/// a subtle scale on reveal unless reduce-motion is on), the "understand, don't
/// just copy" moment.
class SolutionTab extends StatefulWidget {
  const SolutionTab({
    super.key,
    required this.result,
    this.onOpenVisual,
    this.onOpenMethods,
    this.onAskMatheasy,
    this.onAttemptPractice,
  });

  final ResultData result;

  /// Opens the Visual Learning tab — the flagship "understand it, don't just
  /// read it" experience. Null in tests / previews (the hero is then omitted).
  final VoidCallback? onOpenVisual;

  /// Opens the Methods tab from the "compare methods" link (§5). Null → hidden.
  final VoidCallback? onOpenMethods;

  /// Opens Numi from the teaching hand-off strip. Null → the strip is hidden.
  final VoidCallback? onAskMatheasy;

  /// Attempts a practice-ladder rung. Null → the ladder renders read-only.
  final ValueChanged<PracticeItem>? onAttemptPractice;

  @override
  State<SolutionTab> createState() => _SolutionTabState();
}

class _SolutionTabState extends State<SolutionTab> {
  int _method = 0;
  int _revealed = 1;
  bool _revealAll = false;

  List<MethodSolution> get _methods => widget.result.methods;

  /// The steps for the selected method: its own structured stepper (§4), else
  /// the top-level steps (exam pick), else derived from its plain-text steps
  /// (the offline mock).
  List<SolutionStep> get _steps {
    if (_methods.isEmpty) return widget.result.steps;
    final method = _methods[_method.clamp(0, _methods.length - 1)];
    if (method.stepperSteps.isNotEmpty) return method.stepperSteps;
    if (method.recommended && widget.result.steps.isNotEmpty) {
      return widget.result.steps;
    }
    return [
      for (final s in method.steps)
        SolutionStep(title: '', resultLatex: s, detail: ''),
    ];
  }

  void _selectMethod(int index) {
    if (index == _method) return;
    setState(() {
      _method = index;
      _revealed = 1;
      _revealAll = false;
    });
  }

  void _next() => setState(
        () => _revealed = (_revealed + 1).clamp(1, _steps.length),
      );

  void _revealEverything() => setState(() => _revealAll = true);

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    final shown = _revealAll ? steps.length : _revealed.clamp(1, steps.length);
    final more = shown < steps.length;
    // The additive teaching layer (spec §5). Null for a v1 payload / when the
    // server attached none → the whole block below is skipped and this tab is
    // byte-identical to today's. Each card also guards its own emptiness.
    final teaching = widget.result.teaching;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Visual Learning is the flagship — surfaced above the steps with more
        // visual weight than the answer banner, so students reach for
        // understanding, not just the final line. (The step-by-step "Play
        // Solution" player itself lives inside the Pro Visual tab.)
        if (widget.onOpenVisual != null) ...[
          _VisualLearningHero(onTap: widget.onOpenVisual!),
          const SizedBox(height: AppSpacing.lg),
        ],
        // --- Teaching: orient BEFORE the steps (concept → why → journey). ---
        if (teaching != null) ...[
          TeachingHeaderCard(header: teaching.header),
          const SizedBox(height: AppSpacing.md),
          if (!teaching.concept.isEmpty || !teaching.overview.isEmpty) ...[
            ConceptOverviewCard(
              concept: teaching.concept,
              overview: teaching.overview,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (teaching.journey.isNotEmpty) ...[
            LearningJourneyRail(
              journey: teaching.journey,
              stepCount: steps.length,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (teaching.header.whyMethodChosen.isNotEmpty ||
              !teaching.methodRationale.isEmpty) ...[
            WhyThisMethodCard(
              header: teaching.header,
              rationale: teaching.methodRationale,
              onCompare: widget.onOpenMethods,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ],
        // A compact one-line intro keeps the brand voice without pushing the
        // steps down the page — the maths, not the chatter, should lead.
        if (widget.result.tutorIntro.isNotEmpty) ...[
          MatheasyBubble(text: widget.result.tutorIntro, avatarSize: 28),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_methods.length > 1) ...[
          _MethodSwitcher(
            methods: _methods,
            selected: _method,
            onSelect: _selectMethod,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (var i = 0; i < shown; i++)
          KeyedSubtree(
            // Key by method+step so switching methods rebuilds fresh cards (so
            // the reveal emphasis re-runs), and re-revealing doesn't re-animate
            // already-shown steps.
            key: ValueKey('m$_method-s$i'),
            child: AppTransitions.slideUp(
              delay: Duration(milliseconds: (i * 40).clamp(0, 200)),
              child: _StepCard(
                step: steps[i],
                number: i + 1,
                isLast: i == steps.length - 1,
                defaultExpanded: i == 0,
                previousLatex: i > 0 ? steps[i - 1].resultLatex : null,
                // Pulse the just-revealed step (the active transformation).
                pulse: more && i == shown - 1,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        if (more)
          _RevealControls(
            current: shown,
            total: steps.length,
            onNext: _next,
            onRevealAll: _revealEverything,
          )
        else if (widget.result.verifyText.isNotEmpty)
          _VerifyCard(text: widget.result.verifyText),
        // --- Teaching: consolidate AFTER the steps (mistakes → takeaway → practice). ---
        if (teaching != null) ...[
          if (teaching.commonMistakes.any((m) => m.mistake.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.lg),
            CommonMistakesCard(mistakes: teaching.commonMistakes),
          ],
          if (!teaching.keyTakeaway.isEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            KeyTakeawayCard(takeaway: teaching.keyTakeaway),
          ],
          if (teaching.practiceLadder != null) ...[
            const SizedBox(height: AppSpacing.lg),
            PracticeLadderCard(
              ladder: teaching.practiceLadder!,
              onAttempt: widget.onAttemptPractice,
            ),
          ],
        ],
        // The graph (§7) — an expander, after the answer + steps. Omitted
        // entirely when the problem isn't a plottable function.
        if (widget.result.graph != null) ...[
          const SizedBox(height: AppSpacing.lg),
          ResultGraphSection(graph: widget.result.graph!),
        ],
        if (teaching != null && widget.onAskMatheasy != null) ...[
          const SizedBox(height: AppSpacing.lg),
          NumiInviteStrip(onAsk: widget.onAskMatheasy),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Method switcher (§5)
// ---------------------------------------------------------------------------

class _MethodSwitcher extends StatelessWidget {
  const _MethodSwitcher({
    required this.methods,
    required this.selected,
    required this.onSelect,
  });

  final List<MethodSolution> methods;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: methods.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => _MethodChip(
          method: methods[i],
          isSelected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  final MethodSolution method;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The unselected chip's star is an emerald label on a card — it needs the
    // tone that stays legible per theme, not the logo tile.
    final emeraldLabel =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '${method.name}${method.recommended ? ', exam pick' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            // Selected carries white content → the interactive emerald.
            color: isSelected ? AppColors.primaryAction : colors.surface,
            borderRadius: AppRadius.pillRadius,
            border: Border.all(
              color: isSelected ? AppColors.primaryAction : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (method.recommended) ...[
                Icon(
                  Icons.star_rounded,
                  size: 15,
                  color: isSelected ? AppColors.white : emeraldLabel,
                ),
                const SizedBox(width: AppSpacing.xxs),
              ],
              Text(
                method.name,
                style: AppTypography.button.copyWith(
                  fontSize: 13,
                  color: isSelected ? AppColors.white : colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reveal controls (one-at-a-time default)
// ---------------------------------------------------------------------------

class _RevealControls extends StatelessWidget {
  const _RevealControls({
    required this.current,
    required this.total,
    required this.onNext,
    required this.onRevealAll,
  });

  final int current;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onRevealAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _railIndent),
      child: Row(
        children: [
          Expanded(
            child: PrimaryButton(
              label: context.l10n.solutionNextStepOf(current, total),
              trailingIcon: Icons.arrow_downward_rounded,
              onPressed: onNext,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Semantics(
            button: true,
            label: context.l10n.solutionRevealAllSteps,
            excludeSemantics: true,
            child: GestureDetector(
              onTap: onRevealAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.md,
                ),
                child: Text(
                  context.l10n.solutionRevealAll,
                  style: AppTypography.button.copyWith(
                    fontSize: 14,
                    color: context.isDark
                        ? AppColors.primaryLight
                        : AppColors.primaryDark,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step card
// ---------------------------------------------------------------------------

class _StepCard extends StatefulWidget {
  const _StepCard({
    required this.step,
    required this.number,
    required this.isLast,
    required this.defaultExpanded,
    required this.previousLatex,
    required this.pulse,
  });

  final SolutionStep step;
  final int number;
  final bool isLast;
  final bool defaultExpanded;

  /// The previous step's expression, for the "what changed" emphasis (null on
  /// the first step).
  final String? previousLatex;

  /// Whether to play the reveal scale-pulse (suppressed under reduce-motion).
  final bool pulse;

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  late bool _expanded = widget.defaultExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isAnswer = widget.isLast;
    // The "Why?" affordance is an emerald label on a card — per-theme tone.
    final emeraldLabel =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    // The reveal scale-pulse wraps the WHOLE card, OUTSIDE the IntrinsicHeight,
    // so the Transform never perturbs the intrinsic-height measurement (which
    // caused a sub-pixel overflow). Suppressed under reduce-motion (§5).
    final pulse = widget.pulse && !MediaQuery.disableAnimationsOf(context);
    // The step has expandable "why" content if it carries the reasoning OR any of
    // the deeper (Pro/full) teaching fields.
    final s = widget.step;
    final hasWhy = s.detail.isNotEmpty ||
        (s.rule?.isNotEmpty ?? false) ||
        (s.explanation?.isNotEmpty ?? false) ||
        (s.commonMistake?.isNotEmpty ?? false);
    // The timeline connector is a positioned line behind the row (not an
    // IntrinsicHeight-stretched Expanded), so the card takes its natural height
    // and can't cause a sub-pixel intrinsic-height overflow.
    final card = Stack(
      children: [
        if (!widget.isLast)
          Positioned(
            left: _railWidth / 2 - 1,
            top: _railWidth,
            bottom: 0,
            child: Container(width: 2, color: colors.border),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Bullet(number: widget.number, highlight: isAnswer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: AppCard(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A compact eyebrow — what this step does, and the operation
                    // applied — sits ABOVE the equation but is deliberately small.
                    // The equation is the hero of the card (equation-first, not
                    // prose-first). Skipped entirely when there's nothing to label.
                    if (widget.step.title.isNotEmpty ||
                        widget.step.operationLabel != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.step.title,
                              style: AppTypography.caption.copyWith(
                                color: colors.textSecondary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          if (widget.step.operationLabel != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            _OperationChip(label: widget.step.operationLabel!),
                          ],
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    _StepExpression(
                      latex: widget.step.resultLatex,
                      previousLatex: widget.previousLatex,
                      isAnswer: isAnswer,
                    ),
                    // Pivotal step: an elicited "your turn" question BEFORE the
                    // reasoning — the generation moment (spec §0.4). A soft nudge:
                    // the "Why?" reveal below is still one tap away.
                    if (widget.step.pivotal &&
                        (widget.step.selfExplainPrompt?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: AppSpacing.md),
                      _SelfExplainBox(prompt: widget.step.selfExplainPrompt!),
                    ],
                    AnimatedCrossFade(
                      duration: AppDurations.fast,
                      crossFadeState: _expanded
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: _StepDetail(step: widget.step),
                      secondChild: const SizedBox(width: double.infinity),
                    ),
                    if (hasWhy) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Text(
                            _expanded
                                ? context.l10n.solutionHideWhy
                                : context.l10n.solutionWhy,
                            style: AppTypography.caption
                                .copyWith(color: emeraldLabel),
                          ),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: AppDurations.fast,
                            child: Icon(Icons.keyboard_arrow_down_rounded,
                                size: 18, color: emeraldLabel),
                          ),
                        ],
                      ),
                    ],
                  ],
                ), // Column
              ), // AppCard
            ), // Expanded
          ], // Row children
        ), // Row
      ), // Padding
    ], // Stack children
    );
    return pulse ? _ScaleIn(child: card) : card;
  }
}

/// Renders a step's expression with the changed-vs-previous span emphasised in
/// the accent colour (spec §5). The colour is the reduce-motion-safe emphasis;
/// on reveal it also scale-pulses unless animations are disabled. Falls back to
/// a plain render + reveal pulse when there's no isolable changed span.
class _StepExpression extends StatelessWidget {
  const _StepExpression({
    required this.latex,
    required this.previousLatex,
    required this.isAnswer,
  });

  final String latex;
  final String? previousLatex;
  final bool isAnswer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emphasized = previousLatex == null
        ? null
        : emphasizeChanged(previousLatex!, latex, colorHex: _accentHex(context));

    // Sized to the content (max 30, down to 22 for a wide line) so a long step
    // fits without scrolling sideways but a short one stays big. Measured from
    // the plain expression; the coloured emphasis is what's actually drawn.
    return AdaptiveMath(
      latex,
      renderLatex: emphasized,
      minFontSize: 22,
      maxFontSize: 30,
      style: AppTypography.headingSmall.copyWith(
        color: isAnswer ? colors.onSuccessContainer : colors.textPrimary,
      ),
    );
  }
}

/// A one-shot subtle grow-in, played once when the widget first mounts.
class _ScaleIn extends StatefulWidget {
  const _ScaleIn({required this.child});

  final Widget child;

  @override
  State<_ScaleIn> createState() => _ScaleInState();
}

class _ScaleInState extends State<_ScaleIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.medium,
  )..forward();

  // Grows in to 1.0 (never past it, so it can't paint outside the step card's
  // box — the card lives inside an IntrinsicHeight). Subtle, per §5.
  late final Animation<double> _scale = Tween<double>(begin: 0.9, end: 1).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      alignment: Alignment.centerLeft,
      child: widget.child,
    );
  }
}

/// The numbered timeline bullet (the connector line is drawn behind the row).
class _Bullet extends StatelessWidget {
  const _Bullet({required this.number, required this.highlight});

  final int number;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: _railWidth,
      height: _railWidth,
      decoration: BoxDecoration(
        // Solid: the number on the answer bullet is white, so this is the
        // interactive emerald (4.78:1), never the 2.97:1 logo tone.
        color: highlight ? AppColors.primaryAction : colors.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: AppTypography.caption.copyWith(
          color: highlight ? AppColors.white : colors.onPrimaryContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _OperationChip extends StatelessWidget {
  const _OperationChip({required this.label});

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

/// The pivotal-step "your turn" prompt — an elicited question shown before the
/// reasoning (spec §0.4). A generation nudge (a QUESTION, never an assertion),
/// not a hard gate: the "Why?" reveal is still one tap away.
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

/// The expandable reasoning for a step: the "why" plus the deeper (Pro) fields —
/// the named rule, the plain explanation, and the common slip at this step —
/// each shown only when present, so a v1 / lite step shows just the "why".
/// (An empty-detail step renders no stray blank line — a benign layout delta
/// from the pre-Phase-3 offline-mock rendering; the real solver always sets why.)
class _StepDetail extends StatelessWidget {
  const _StepDetail({required this.step});

  final SolutionStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rule = step.rule;
    final explanation = step.explanation;
    final mistake = step.commonMistake;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (step.detail.isNotEmpty)
            Text(
              step.detail,
              style: AppTypography.bodySmall
                  .copyWith(color: colors.textSecondary),
            ),
          if (rule != null && rule.isNotEmpty) ...[
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
                      rule,
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
      ),
    );
  }
}

/// The flagship Visual Learning entry — a premium, gold-accented card that
/// out-weighs the answer banner, nudging students toward the animated
/// walkthrough (understand the solution, don't just read the final line). Taps
/// jump to the Visual tab, where free users meet the unlock and Pro users the
/// full experience — monetization is unchanged.
class _VisualLearningHero extends StatelessWidget {
  const _VisualLearningHero({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.l10n.solutionOpenVisualLearning,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: const BoxDecoration(
            gradient: AppColors.premiumGradient,
            borderRadius: AppRadius.cardRadius,
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 24, color: AppColors.goldLight),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.resultVisualLearningLabel,
                      style: AppTypography.label
                          .copyWith(color: AppColors.goldLight),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.l10n.solutionVisualHeroTitle,
                      style: AppTypography.headingSmall
                          .copyWith(color: AppColors.white),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      context.l10n.solutionVisualHeroSubtitle,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.arrow_forward_rounded,
                  size: 22, color: AppColors.white),
            ],
          ),
        ),
      ),
    );
  }
}


class _VerifyCard extends StatelessWidget {
  const _VerifyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: _railIndent),
      child: MatheasyBubble(text: text),
    );
  }
}
