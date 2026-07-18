import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/animations/app_transitions.dart';
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
import 'visual_shared_widgets.dart';

/// Tier 1 — animated equation transformations (the Photomath-inspired
/// experience). One step is on stage at a time: the expression before, the
/// operation applied, and the expression after, cross-fading between steps
/// with auto-play that respects reduced motion.
class Tier1AnimatedTransformation extends StatefulWidget {
  const Tier1AnimatedTransformation({
    super.key,
    required this.visual,
    required this.onAskMatheasy,
  });

  final VisualSolution visual;

  /// Called with the index of the step on stage when the student asks Matheasy.
  final ValueChanged<int> onAskMatheasy;

  @override
  State<Tier1AnimatedTransformation> createState() =>
      _Tier1AnimatedTransformationState();
}

class _Tier1AnimatedTransformationState
    extends State<Tier1AnimatedTransformation> {
  int _index = 0;
  bool _playing = false;
  bool _autoplayDecided = false;
  Timer? _timer;

  List<VisualStep> get _steps => widget.visual.steps;
  bool get _isLast => _index >= _steps.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-play once on open, like the Play Solution walkthrough — but never
    // when the user asked for reduced motion (they advance manually).
    if (_autoplayDecided) return;
    _autoplayDecided = true;
    if (!MediaQuery.disableAnimationsOf(context) && _steps.length > 1) {
      _play();
    }
  }

  @override
  void didUpdateWidget(Tier1AnimatedTransformation oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A retry can hand back a solution with fewer steps while _index points
    // past the new end — clamp so the stage never reads out of range.
    if (_index >= _steps.length) {
      _index = _steps.isEmpty ? 0 : _steps.length - 1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    _timer = Timer.periodic(AppDurations.walkthroughStep, (_) {
      if (_isLast) {
        _pause();
      } else {
        setState(() => _index++);
      }
    });
    setState(() => _playing = true);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    setState(() => _playing = false);
  }

  /// Manual navigation takes over from auto-play.
  void _goTo(int index) {
    _pause();
    setState(() => _index = index.clamp(0, _steps.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final visual = widget.visual;
    final step = _steps[_index];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(text: visual.intro),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'STEP ${_index + 1} OF ${_steps.length}',
                    style: AppTypography.label
                        .copyWith(color: colors.textMuted),
                  ),
                  const Spacer(),
                  if (!reduceMotion && _steps.length > 1)
                    _PlayPauseButton(
                      playing: _playing,
                      onPressed: _playing ? _pause : _play,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : AppDurations.medium,
                transitionBuilder: AppTransitions.fadeThrough,
                child: KeyedSubtree(
                  key: ValueKey(_index),
                  child: _StepStage(step: step, reduceMotion: reduceMotion),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: _ProgressDots(
            count: _steps.length,
            index: _index,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: context.l10n.resultBack,
                icon: Icons.chevron_left_rounded,
                size: AppButtonSize.medium,
                onPressed: _index == 0 ? null : () => _goTo(_index - 1),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                label: _isLast ? context.l10n.visualReplay : context.l10n.actionNext,
                trailingIcon: _isLast
                    ? Icons.replay_rounded
                    : Icons.chevron_right_rounded,
                size: AppButtonSize.medium,
                onPressed: () => _goTo(_isLast ? 0 : _index + 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AskMatheasyButton(onPressed: () => widget.onAskMatheasy(_index)),
        if (visual.concept != null) ...[
          const SizedBox(height: AppSpacing.md),
          VisualConceptView(concept: visual.concept!),
        ],
        if (visual.explanation != null && _isLast) ...[
          const SizedBox(height: AppSpacing.md),
          AppTransitions.fadeIn(
            child: VisualKeyIdeasCard(explanation: visual.explanation!),
          ),
        ],
        if (visual.method != null) ...[
          const SizedBox(height: AppSpacing.md),
          VisualMethodCard(method: visual.method!),
        ],
      ],
    );
  }
}

/// The stage for one step: before → operation → after, with the "after" line
/// arriving last so the transformation reads top-to-bottom.
class _StepStage extends StatelessWidget {
  const _StepStage({required this.step, required this.reduceMotion});

  final VisualStep step;
  final bool reduceMotion;

  /// Entrance staggering inside the stage; skipped under reduced motion.
  Widget _entrance(Widget child, {required int order}) {
    if (reduceMotion) return child;
    return AppTransitions.slideUp(
      delay: Duration(milliseconds: order * 140),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Rendered math carries no semantics — announce the whole transformation
    // as one sentence instead of three fragments.
    return Semantics(
      container: true,
      label: step.semanticDescription,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              step.title,
              style: AppTypography.bodyMedium.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AdaptiveMath(
              step.beforeLatex,
              minFontSize: 24,
              maxFontSize: 30,
              alignment: Alignment.center,
              style: AppTypography.headingSmall
                  .copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            _entrance(
              order: 1,
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (step.operationLabel != null) ...[
                    VisualOperationChip(label: step.operationLabel!),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Icon(
                    Icons.arrow_downward_rounded,
                    size: 20,
                    color: context.isDark
                        ? AppColors.primaryLight
                        : AppColors.primaryDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _entrance(
              order: 2,
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: AppRadius.mdRadius,
                ),
                child: AdaptiveMath(
                  step.afterLatex,
                  minFontSize: 28,
                  maxFontSize: 36,
                  alignment: Alignment.center,
                  style: AppTypography.headingMedium
                      .copyWith(color: colors.onPrimaryContainer),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _entrance(
              order: 3,
              Text(
                step.explanation,
                style: AppTypography.bodySmall
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: playing
          ? context.l10n.resultPauseWalkthrough
          : context.l10n.resultPlayWalkthroughShort,
      iconSize: 22,
      // 44px minimum tap target.
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(
        playing ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
        color:
            context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Step ${index + 1} of $count',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: AppDurations.fast,
                curve: AppCurves.standard,
                width: i == index ? 18 : 6,
                height: 6,
                margin:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: i == index
                      ? (context.isDark
                          ? AppColors.primaryLight
                          : AppColors.primaryDark)
                      : colors.border,
                  borderRadius: AppRadius.pillRadius,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
