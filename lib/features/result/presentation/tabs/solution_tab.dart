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

/// Diameter of the numbered rail bullets; trailing content indents past it.
const double _railWidth = 30;
const double _railIndent = _railWidth + AppSpacing.md;

/// Tab 1 — the step-by-step worked solution. Each step is an interactive card:
/// the transformed equation is always visible, and tapping reveals the "why".
class SolutionTab extends StatelessWidget {
  const SolutionTab({super.key, required this.result});

  final ResultData result;

  @override
  Widget build(BuildContext context) {
    final steps = result.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NumiBubble(text: result.numiIntro),
        const SizedBox(height: AppSpacing.lg),
        for (var i = 0; i < steps.length; i++)
          AppTransitions.slideUp(
            delay: Duration(milliseconds: (i * 60).clamp(0, 300)),
            child: _StepCard(
              step: steps[i],
              number: i + 1,
              isLast: i == steps.length - 1,
              defaultExpanded: i == 0,
            ),
          ),
        const SizedBox(height: AppSpacing.xs),
        _VerifyCard(text: result.verifyText),
      ],
    );
  }
}

class _StepCard extends StatefulWidget {
  const _StepCard({
    required this.step,
    required this.number,
    required this.isLast,
    required this.defaultExpanded,
  });

  final SolutionStep step;
  final int number;
  final bool isLast;
  final bool defaultExpanded;

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  late bool _expanded = widget.defaultExpanded;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isAnswer = widget.isLast;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Rail(number: widget.number, isLast: widget.isLast, highlight: isAnswer),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
                    MathText(
                      widget.step.resultLatex,
                      style: AppTypography.headingSmall.copyWith(
                        // onSuccessContainer == successDeep in light mode and
                        // stays legible on dark surfaces.
                        color: isAnswer
                            ? colors.onSuccessContainer
                            : colors.textPrimary,
                        fontSize: 23,
                      ),
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
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.number,
    required this.isLast,
    required this.highlight,
  });

  final int number;
  final bool isLast;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        Container(
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
        ),
        if (!isLast)
          Expanded(
            child: Container(
              width: 2,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              color: colors.border,
            ),
          ),
      ],
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
      child: NumiBubble(text: text),
    );
  }
}
