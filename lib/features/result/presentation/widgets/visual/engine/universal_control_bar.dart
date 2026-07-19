import 'package:flutter/material.dart';

import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/theme/app_durations.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../domain/animation/animation_script.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the shared control bar every renderer
/// uses: Previous · Play/Pause · a scrubbable progress bar · a speed selector
/// (0.5×–2×) · Next/Replay. All 44dp targets, localized, reduced-motion aware
/// (Play/Pause and speed hide when motion is off — the student steps manually).
class UniversalControlBar extends StatelessWidget {
  const UniversalControlBar({
    super.key,
    required this.index,
    required this.total,
    required this.playing,
    required this.reduceMotion,
    required this.speed,
    required this.onPrev,
    required this.onNext,
    required this.onPlayPause,
    required this.onCycleSpeed,
    required this.onSeek,
  });

  final int index;
  final int total;
  final bool playing;
  final bool reduceMotion;
  final PlaybackSpeed speed;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback onCycleSpeed;

  /// Seek to a step (0..total-1) from the scrubber.
  final ValueChanged<int> onSeek;

  bool get _isLast => index >= total - 1;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Row(
      children: [
        _RoundIcon(
          icon: Icons.first_page_rounded,
          tooltip: context.l10n.resultPreviousStep,
          onPressed: onPrev,
          color: colors.textSecondary,
        ),
        if (!reduceMotion)
          _RoundIcon(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: playing ? context.l10n.visualPause : context.l10n.visualPlay,
            onPressed: onPlayPause,
            color: emerald,
            filled: true,
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: _Scrubber(
              index: index,
              total: total,
              active: emerald,
              idle: colors.border,
              onSeek: onSeek,
            ),
          ),
        ),
        if (!reduceMotion)
          _SpeedChip(speed: speed, color: emerald, onTap: onCycleSpeed),
        _RoundIcon(
          icon: _isLast ? Icons.replay_rounded : Icons.last_page_rounded,
          tooltip:
              _isLast ? context.l10n.visualReplay : context.l10n.resultNextStep,
          onPressed: onNext,
          color: emerald,
        ),
      ],
    );
  }
}

/// A draggable step scrubber. Tap or drag along the bar to seek a step.
class _Scrubber extends StatelessWidget {
  const _Scrubber({
    required this.index,
    required this.total,
    required this.active,
    required this.idle,
    required this.onSeek,
  });

  final int index;
  final int total;
  final Color active;
  final Color idle;
  final ValueChanged<int> onSeek;

  void _seekFromDx(double dx, double width) {
    if (total <= 1 || width <= 0) return;
    final frac = (dx / width).clamp(0.0, 1.0);
    final target = (frac * (total - 1)).round();
    if (target != index) onSeek(target);
  }

  @override
  Widget build(BuildContext context) {
    final fill = total <= 1 ? 1.0 : index / (total - 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Semantics(
          slider: true,
          label: context.l10n.resultStepOfTotal(index + 1, total),
          value: '${index + 1}',
          // Flutter requires value + increased/decreasedValue together when an
          // adjust action is wired.
          increasedValue: '${(index + 2).clamp(1, total)}',
          decreasedValue: '${index.clamp(1, total)}',
          // Assistive "adjust" gestures dispatch increase/decrease, not raw
          // drags — wire them to seek so VoiceOver/TalkBack can scrub too.
          onIncrease: index >= total - 1
              ? null
              : () => onSeek((index + 1).clamp(0, total - 1)),
          onDecrease: index <= 0
              ? null
              : () => onSeek((index - 1).clamp(0, total - 1)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _seekFromDx(d.localPosition.dx, width),
            onHorizontalDragUpdate: (d) =>
                _seekFromDx(d.localPosition.dx, width),
            child: SizedBox(
              height: 44,
              child: Center(
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: idle,
                        borderRadius: AppRadius.pillRadius,
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: fill.clamp(0.0, 1.0),
                      child: AnimatedContainer(
                        duration: AppDurations.fast,
                        height: 5,
                        decoration: BoxDecoration(
                          color: active,
                          borderRadius: AppRadius.pillRadius,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment(fill.clamp(0.0, 1.0) * 2 - 1, 0),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: active,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: context.colors.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SpeedChip extends StatelessWidget {
  const _SpeedChip(
      {required this.speed, required this.color, required this.onTap});

  final PlaybackSpeed speed;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: context.l10n.engineSpeed,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.pillRadius,
            ),
            child: Text(
              speed.label,
              style: AppTypography.label.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
    this.filled = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 22,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      style: filled
          ? IconButton.styleFrom(
              backgroundColor: colors.primaryContainer,
              foregroundColor: colors.onPrimaryContainer,
            )
          : null,
      color: filled ? colors.onPrimaryContainer : color,
      icon: Icon(icon),
    );
  }
}
