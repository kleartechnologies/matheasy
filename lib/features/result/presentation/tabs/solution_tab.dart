import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import '../widgets/math_text.dart';
import '../widgets/result_graph.dart';
import '../widgets/step_diff.dart';

/// Diameter of the numbered rail bullets; trailing content indents past it.
const double _railWidth = 30;
const double _railIndent = _railWidth + AppSpacing.md;

/// The emerald accent used to highlight the changed span of a step (§5).
const String _accentHex = '#10B981';

/// Tab 1 — the step-by-step worked solution (spec §4/§5).
///
/// The stepper reveals ONE step at a time by default ("Next step"), with a
/// "Reveal all" toggle, and — when there is more than one method — a switcher so
/// each method drives its own stepper (the exam pick is badged). Every step past
/// the first highlights WHAT CHANGED from the previous step (accent colour, plus
/// a subtle scale on reveal unless reduce-motion is on), the "understand, don't
/// just copy" moment.
class SolutionTab extends StatefulWidget {
  const SolutionTab({super.key, required this.result});

  final ResultData result;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(text: widget.result.tutorIntro),
        if (_methods.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          _MethodSwitcher(
            methods: _methods,
            selected: _method,
            onSelect: _selectMethod,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
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
        else
          _VerifyCard(text: widget.result.verifyText),
        // The graph (§7) — an expander, after the answer + steps. Omitted
        // entirely when the problem isn't a plottable function.
        if (widget.result.graph != null) ...[
          const SizedBox(height: AppSpacing.lg),
          ResultGraphSection(graph: widget.result.graph!),
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
            color: isSelected ? AppColors.primary : colors.surface,
            borderRadius: AppRadius.pillRadius,
            border: Border.all(
              color: isSelected ? AppColors.primary : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (method.recommended) ...[
                Icon(
                  Icons.star_rounded,
                  size: 15,
                  color: isSelected ? AppColors.white : AppColors.primary,
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
              label: 'Next step · $current of $total',
              trailingIcon: Icons.arrow_downward_rounded,
              onPressed: onNext,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Semantics(
            button: true,
            label: 'Reveal all steps',
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
                  'Reveal all',
                  style: AppTypography.button.copyWith(
                    fontSize: 14,
                    color: AppColors.primary,
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
    // The reveal scale-pulse wraps the WHOLE card, OUTSIDE the IntrinsicHeight,
    // so the Transform never perturbs the intrinsic-height measurement (which
    // caused a sub-pixel overflow). Suppressed under reduce-motion (§5).
    final pulse = widget.pulse && !MediaQuery.disableAnimationsOf(context);
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.step.title,
                            style: AppTypography.bodyMedium.copyWith(
                              color: colors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (widget.step.operationLabel != null)
                          _OperationChip(label: widget.step.operationLabel!),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _StepExpression(
                      latex: widget.step.resultLatex,
                      previousLatex: widget.previousLatex,
                      isAnswer: isAnswer,
                    ),
                    AnimatedCrossFade(
                      duration: AppDurations.fast,
                      crossFadeState: _expanded
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text(
                          widget.step.detail,
                          style: AppTypography.bodySmall
                              .copyWith(color: colors.textSecondary),
                        ),
                      ),
                      secondChild: const SizedBox(width: double.infinity),
                    ),
                    if (widget.step.detail.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Text(
                            _expanded ? 'Hide why' : 'Why?',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.primary),
                          ),
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0,
                            duration: AppDurations.fast,
                            child: const Icon(Icons.keyboard_arrow_down_rounded,
                                size: 18, color: AppColors.primary),
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
        : emphasizeChanged(previousLatex!, latex, colorHex: _accentHex);

    return MathText(
      emphasized ?? latex,
      style: AppTypography.headingSmall.copyWith(
        color: isAnswer ? colors.onSuccessContainer : colors.textPrimary,
        fontSize: 23,
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
        gradient: highlight ? AppColors.primaryGradient : null,
        color: highlight ? null : colors.primaryContainer,
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
