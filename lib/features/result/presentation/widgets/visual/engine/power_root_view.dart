import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../../core/animations/app_transitions.dart';
import '../../../../../../core/animations/pressable.dart';
import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/theme/app_durations.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../domain/animation/power_root.dart';
import '../../math_text.dart';

/// A Photomath-style POWERS & ROOTS tutorial (e.g. `2^5`, `√144`): a power
/// expands into repeated multiplication with a running product; a root asks
/// "what number, raised to k, gives n?". Driven by the verified [PowerRoot]
/// model. The math line renders with the real renderer; the callout is prose.
class PowerRootView extends StatefulWidget {
  const PowerRootView({super.key, required this.model, this.onAskStep});

  final PowerRoot model;
  final ValueChanged<int>? onAskStep;

  @override
  State<PowerRootView> createState() => _PowerRootViewState();
}

class _PowerRootViewState extends State<PowerRootView> {
  int _index = 0;
  Timer? _timer;
  bool _playing = false;

  int get _last => widget.model.steps.length - 1;
  bool get _isLast => _index == _last;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _go(int i) {
    setState(() => _index = i.clamp(0, _last));
    if (_playing) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_isLast) {
      setState(() => _playing = false);
      return;
    }
    _timer = Timer(const Duration(milliseconds: 1600), () => _go(_index + 1));
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      if (_isLast) _go(0);
      _schedule();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.model.steps[_index];
    final colors = context.colors;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepIndicator(index: _index, total: widget.model.steps.length),
        const SizedBox(height: AppSpacing.xl),
        SizedBox(
          height: 96,
          child: Center(
            child: AnimatedSwitcher(
              duration: AppDurations.medium,
              transitionBuilder: AppTransitions.fadeThrough,
              child: Padding(
                key: ValueKey(_index),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AdaptiveMath(
                  step.latex,
                  minFontSize: 24,
                  maxFontSize: 46,
                  alignment: Alignment.center,
                  style: AppTypography.displayMedium
                      .copyWith(color: colors.textPrimary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (step.callout != null)
          _CalloutPill(text: step.callout!, background: AppColors.accentCoral),
        const SizedBox(height: AppSpacing.lg),
        _Caption(text: step.caption),
        const SizedBox(height: AppSpacing.md),
        _Controls(
          index: _index,
          isLast: _isLast,
          playing: _playing,
          onPrev: () => _go(_index - 1),
          onNext: () => _go(_index + 1),
          onReplay: () => _go(0),
          onTogglePlay: _togglePlay,
        ),
        if (widget.onAskStep != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _AskButton(onTap: () => widget.onAskStep!(_index)),
        ],
      ],
    );
  }
}

class _CalloutPill extends StatelessWidget {
  const _CalloutPill({required this.text, required this.background});

  final String text;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fill = context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Column(
      children: [
        Text(
          context.l10n.resultStepOfUpper(index + 1, total),
          style: AppTypography.label.copyWith(color: fill),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xxs),
              Container(
                width: i == index ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i <= index ? fill : context.colors.surfaceMuted,
                  borderRadius: AppRadius.pillRadius,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppTypography.bodyLarge.copyWith(color: context.colors.textSecondary),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.index,
    required this.isLast,
    required this.playing,
    required this.onPrev,
    required this.onNext,
    required this.onReplay,
    required this.onTogglePlay,
  });

  final int index;
  final bool isLast;
  final bool playing;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onReplay;
  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(context,
            icon: Icons.arrow_back_rounded,
            label: context.l10n.resultPreviousStep,
            onTap: index > 0 ? onPrev : null),
        const SizedBox(width: AppSpacing.md),
        _circle(context,
            icon: isLast
                ? Icons.replay_rounded
                : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
            label: context.l10n.resultPlayWalkthroughShort,
            filled: true,
            onTap: isLast ? onReplay : onTogglePlay),
        const SizedBox(width: AppSpacing.md),
        _circle(context,
            icon: Icons.arrow_forward_rounded,
            label: context.l10n.resultNextStep,
            onTap: isLast ? null : onNext),
      ],
    );
  }

  Widget _circle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool filled = false,
  }) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: label,
      child: Pressable(
        onTap: onTap ?? () {},
        scale: enabled ? 0.92 : 1,
        borderRadius: AppRadius.pillRadius,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: filled ? AppColors.primaryAction : colors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 24, color: filled ? AppColors.white : colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _AskButton extends StatelessWidget {
  const _AskButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Semantics(
      button: true,
      label: context.l10n.tutorAsk,
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline_rounded, size: 16, color: emerald),
            const SizedBox(width: AppSpacing.xxs),
            Text(context.l10n.tutorAsk,
                style: AppTypography.caption.copyWith(color: emerald)),
          ],
        ),
      ),
    );
  }
}
