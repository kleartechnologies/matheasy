import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/animations/floaty.dart';
import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/result_models.dart';
import 'math_text.dart';

/// The "Play Solution" experience — a guided walkthrough that auto-advances
/// through the steps with Matheasy narrating, a progress bar, and play/pause +
/// step controls.
///
/// FUTURE-READY (voice): each step exposes a single narration point
/// ([_narrate]). Wiring a TTS engine there gives spoken explanations without
/// touching this UI.
class PlaySolutionOverlay extends StatefulWidget {
  const PlaySolutionOverlay({
    super.key,
    required this.steps,
    required this.verifyText,
    this.autoPlay = true,
  });

  final List<SolutionStep> steps;
  final String verifyText;
  final bool autoPlay;

  /// Presents the walkthrough as a blurred modal.
  static Future<void> show(
    BuildContext context, {
    required List<SolutionStep> steps,
    required String verifyText,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Play Solution',
      barrierColor: context.colors.scrim,
      transitionDuration: AppDurations.medium,
      pageBuilder: (_, _, _) =>
          PlaySolutionOverlay(steps: steps, verifyText: verifyText),
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
  State<PlaySolutionOverlay> createState() => _PlaySolutionOverlayState();
}

class _PlaySolutionOverlayState extends State<PlaySolutionOverlay> {
  int _index = 0;
  late bool _playing = widget.autoPlay;
  Timer? _timer;

  int get _lastIndex => widget.steps.length - 1;
  bool get _isLast => _index == _lastIndex;

  @override
  void initState() {
    super.initState();
    _narrate();
    if (_playing) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Voice hook — Stage 6 connects TTS here to speak the current step.
  void _narrate() {
    // Voice (Stage 6): synthesize widget.steps[_index].detail via the tutor.
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(AppDurations.walkthroughStep, () {
      if (_isLast) {
        setState(() => _playing = false);
      } else {
        _go(_index + 1);
      }
    });
  }

  void _go(int index) {
    setState(() => _index = index.clamp(0, _lastIndex));
    _narrate();
    if (_playing && !_isLast) {
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing && !_isLast) {
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final step = widget.steps[_index];

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
                // This modal is the one surface in the flow that doesn't sit in
                // a ListView, so bound it to the screen: the enlarged step math
                // and any text-scaled narration scroll vertically here instead of
                // painting an overflow stripe on a small device.
                child: SingleChildScrollView(
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _isLast ? 'SOLVED' : 'STEP ${_index + 1} OF '
                              '${widget.steps.length}',
                          style: AppTypography.label.copyWith(
                            color: context.isDark
                                ? AppColors.primaryLight
                                : AppColors.primaryDark,
                          ),
                        ),
                        const Spacer(),
                        _CircleButton(
                          icon: Icons.close_rounded,
                          semanticLabel: 'Close walkthrough',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Floaty(child: MatheasyBrandAvatar(size: 64)),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: colors.surfaceMuted,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(AppRadius.lg),
                                topRight: Radius.circular(AppRadius.lg),
                                bottomLeft: Radius.circular(6),
                                bottomRight: Radius.circular(AppRadius.lg),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  step.title,
                                  style: AppTypography.title
                                      .copyWith(color: colors.textPrimary),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                Text(
                                  _isLast ? widget.verifyText : step.detail,
                                  style: AppTypography.bodySmall
                                      .copyWith(color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        borderRadius: AppRadius.lgRadius,
                      ),
                      child: Column(
                        children: [
                          if (step.operationLabel != null) ...[
                            Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.warningContainer,
                                  borderRadius: AppRadius.smRadius,
                                ),
                                child: Text(
                                  step.operationLabel!,
                                  style: AppTypography.label.copyWith(
                                    color: colors.onWarningContainer,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                          AnimatedSwitcher(
                            duration: AppDurations.medium,
                            transitionBuilder: AppTransitions.fadeThrough,
                            child: AdaptiveMath(
                              step.resultLatex,
                              key: ValueKey(_index),
                              // Read at arm's length: keep the current step big
                              // (up to 44px) but size it down to fit rather than
                              // scroll sideways.
                              minFontSize: 30,
                              maxFontSize: 44,
                              alignment: Alignment.center,
                              style: AppTypography.displaySmall
                                  .copyWith(color: colors.onPrimaryContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _Progress(count: widget.steps.length, current: _index),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        if (_index > 0) ...[
                          _CircleButton(
                            icon: Icons.arrow_back_rounded,
                            semanticLabel: 'Previous step',
                            onTap: () => _go(_index - 1),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        _CircleButton(
                          icon: _playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          semanticLabel:
                              _playing ? 'Pause walkthrough' : 'Play walkthrough',
                          onTap: _togglePlay,
                          filled: true,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: _PrimaryPill(
                            label: _isLast ? 'Got it!' : 'Next step',
                            icon: _isLast
                                ? Icons.check_circle_rounded
                                : Icons.arrow_forward_rounded,
                            onTap: _isLast
                                ? () => Navigator.of(context).pop()
                                : () => _go(_index + 1),
                          ),
                        ),
                      ],
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

class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    // The filled track must clear 3:1 as a non-text graphic against the surface
    // it sits on, which the logo tone (2.97:1) does not.
    final fill = context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AnimatedContainer(
              duration: AppDurations.medium,
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

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
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
            // Solid: the filled variant carries a white icon (4.78:1).
            color: filled ? AppColors.primaryAction : colors.surfaceMuted,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 22,
            color: filled ? AppColors.white : colors.textSecondary,
          ),
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
          // Solid: this pill's label is white. The old gradient's top stop put
          // it at 1.92:1; primaryAction is 4.78:1.
          color: AppColors.primaryAction,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style:
                  AppTypography.button.copyWith(color: AppColors.white, fontSize: 15),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(icon, size: 20, color: AppColors.white),
          ],
        ),
      ),
    );
  }
}
