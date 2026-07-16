import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../core/extensions/context_extensions.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_durations.dart';
import '../../../../../core/theme/app_radius.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/geometry_models.dart';
import '../../../domain/visual_models.dart';
import '../math_text.dart';
import 'geometry_scene_painter.dart';
import 'visual_shared_widgets.dart';

/// The **diagram-first** geometry renderer — the flagship of the Visual tab for
/// geometry problems. Unlike the text-heavy concept explorer, here the drawing
/// is the primary element (a **70 / 20 / 10** split of diagram, step text and
/// controls). The animated [GeometryScenePainter] reveals the solution one beat
/// at a time: highlight the givens → show the rule → find the missing angle →
/// stamp the answer on the figure.
///
/// Every measure it draws comes from the deterministically-solved
/// [GeometryScene]; this widget only sequences and animates it.
class GeometryVisualPlayer extends StatefulWidget {
  const GeometryVisualPlayer({
    super.key,
    required this.visual,
    required this.scene,
    required this.onAskMatheasy,
  });

  final VisualSolution visual;
  final GeometryScene scene;

  /// Called with the active step index when the student asks Matheasy.
  final ValueChanged<int> onAskMatheasy;

  @override
  State<GeometryVisualPlayer> createState() => _GeometryVisualPlayerState();
}

class _GeometryVisualPlayerState extends State<GeometryVisualPlayer>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppDurations.slow,
  );
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  int _index = 0;
  bool _playing = false;
  bool _decidedAutoplay = false;
  Timer? _timer;

  List<GeometryStep> get _steps => widget.scene.steps;
  bool get _isLast => _index >= _steps.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    if (!_decidedAutoplay) {
      _decidedAutoplay = true;
      if (reduceMotion) {
        _entrance.value = 1;
      } else {
        _pulse.repeat(reverse: true);
        _entrance.forward(from: 0);
        if (_steps.length > 1) _play();
      }
      return;
    }

    // The user turned Reduce Motion ON while a walkthrough was auto-playing:
    // stop the timer and the repeating pulse at once (the Pause button is also
    // hidden under reduced motion, so autoplay must not outlive the toggle).
    if (reduceMotion) {
      _pause();
      _pulse.stop();
      _entrance.value = 1;
    }
  }

  @override
  void didUpdateWidget(GeometryVisualPlayer old) {
    super.didUpdateWidget(old);
    // A retry can hand back a scene with fewer steps.
    if (_index >= _steps.length) {
      _index = _steps.isEmpty ? 0 : _steps.length - 1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    _timer = Timer.periodic(AppDurations.walkthroughStep, (_) {
      if (_isLast) {
        _pause();
      } else {
        _goTo(_index + 1, fromTimer: true);
      }
    });
    setState(() => _playing = true);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _playing = false);
  }

  void _goTo(int index, {bool fromTimer = false}) {
    if (!fromTimer) _pause();
    setState(() => _index = index.clamp(0, _steps.length - 1));
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else {
      _entrance.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) return const SizedBox.shrink();
    final colors = context.colors;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final palette = _paletteFor(context);

    // The player owns a large, diagram-first region sized from the viewport so
    // the drawing dominates (≈70%), with the step text (≈20%) and controls
    // (≈10%) beneath it. Secondary cards then scroll below the region.
    final viewport = MediaQuery.sizeOf(context).height;
    final playerHeight = (viewport * 0.66).clamp(380.0, 640.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: playerHeight,
          child: Column(
            children: [
              // 70% — the animated diagram.
              Expanded(
                flex: 7,
                child: _Diagram(
                  scene: widget.scene,
                  index: _index,
                  entrance: _entrance,
                  pulse: _pulse,
                  palette: palette,
                  reduceMotion: reduceMotion,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // 20% — the compact step explanation.
              Expanded(
                flex: 2,
                child: _StepStrip(
                  step: _steps[_index],
                  index: _index,
                  total: _steps.length,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // ~10% — the controls. A fixed height (not a flex) so the 44dp
              // tap targets survive even when the region clamps small.
              SizedBox(
                height: 48,
                child: _Controls(
                  index: _index,
                  total: _steps.length,
                  playing: _playing,
                  reduceMotion: reduceMotion,
                  onBack: _index == 0 ? null : () => _goTo(_index - 1),
                  onNext: () => _goTo(_isLast ? 0 : _index + 1),
                  onPlayPause: _playing ? _pause : _play,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Secondary, scrollable content — never competes with the diagram.
        AskMatheasyButton(onPressed: () => widget.onAskMatheasy(_index)),
        _RuleChip(ruleName: widget.scene.ruleName, color: colors.textSecondary),
        if (widget.visual.explanation != null) ...[
          const SizedBox(height: AppSpacing.md),
          VisualKeyIdeasCard(explanation: widget.visual.explanation!),
        ],
        if (widget.visual.method != null) ...[
          const SizedBox(height: AppSpacing.md),
          VisualMethodCard(method: widget.visual.method!),
        ],
      ],
    );
  }

  GeometryPalette _paletteFor(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return GeometryPalette(
      figureStroke: colors.textSecondary,
      figureFill: emerald.withValues(alpha: 0.07),
      knownArc: emerald,
      highlight: AppColors.warning,
      // On-canvas text needs AA on the card; amber clears it on light but not
      // on dark, where onWarningContainer does.
      highlightText:
          context.isDark ? colors.onWarningContainer : AppColors.warning,
      vertexDot: colors.textMuted,
      text: colors.textPrimary,
      dim: colors.textMuted.withValues(alpha: 0.55),
      badgeBackground: colors.warningContainer,
      badgeText: colors.onWarningContainer,
      tick: emerald,
    );
  }
}

/// The animated diagram card — the 70% hero. Rebuilds each frame off the two
/// controllers and paints the current reveal state.
class _Diagram extends StatelessWidget {
  const _Diagram({
    required this.scene,
    required this.index,
    required this.entrance,
    required this.pulse,
    required this.palette,
    required this.reduceMotion,
  });

  final GeometryScene scene;
  final int index;
  final AnimationController entrance;
  final AnimationController pulse;
  final GeometryPalette palette;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Semantics(
        image: true,
        // Step-aware so VoiceOver users hear only what's revealed — the answer
        // is announced on the answer beat, never before it.
        label: scene.semanticsForStep(index),
        child: ExcludeSemantics(
          child: InteractiveViewer(
            maxScale: 4,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([entrance, pulse]),
                builder: (context, _) {
                  final progress = reduceMotion
                      ? 1.0
                      : Curves.easeOut.transform(entrance.value);
                  final glow = reduceMotion ? 1.0 : pulse.value;
                  return CustomPaint(
                    size: Size.infinite,
                    painter: GeometryScenePainter(
                      scene: scene,
                      revealStep: index,
                      stepProgress: progress,
                      pulse: glow,
                      palette: palette,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 20% step strip — the current beat's heading, rule/rearrangement math and
/// one plain sentence. Scrolls internally if a device shrinks the region so it
/// can never overflow.
class _StepStrip extends StatelessWidget {
  const _StepStrip({
    required this.step,
    required this.index,
    required this.total,
  });

  final GeometryStep step;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Semantics(
      liveRegion: true,
      label: 'Step ${index + 1} of $total. ${step.semanticLabel}',
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'STEP ${index + 1} OF $total · ${step.title.toUpperCase()}',
                textAlign: TextAlign.center,
                style: AppTypography.label.copyWith(color: emerald),
              ),
              if (step.equationLatex != null) ...[
                const SizedBox(height: AppSpacing.xs),
                // FittedBox scales the equation down to fit the strip width so a
                // long rearrangement never overflows the card.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: MathText(
                    step.equationLatex!,
                    style: AppTypography.headingSmall
                        .copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                step.detail,
                textAlign: TextAlign.center,
                style:
                    AppTypography.bodySmall.copyWith(color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 10% control bar — Back / Play-Pause / Next plus step dots.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.index,
    required this.total,
    required this.playing,
    required this.reduceMotion,
    required this.onBack,
    required this.onNext,
    required this.onPlayPause,
  });

  final int index;
  final int total;
  final bool playing;
  final bool reduceMotion;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final isLast = index >= total - 1;
    return Row(
      children: [
        _RoundIcon(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Previous step',
          onPressed: onBack,
          color: colors.textSecondary,
        ),
        if (!reduceMotion) ...[
          const SizedBox(width: AppSpacing.sm),
          _RoundIcon(
            icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            tooltip: playing ? 'Pause' : 'Play',
            onPressed: onPlayPause,
            color: emerald,
            filled: true,
          ),
        ],
        Expanded(
          child: Center(
            child: _Dots(count: total, index: index, color: emerald,
                idle: colors.border),
          ),
        ),
        _RoundIcon(
          icon: isLast ? Icons.replay_rounded : Icons.chevron_right_rounded,
          tooltip: isLast ? 'Replay' : 'Next step',
          onPressed: onNext,
          color: emerald,
        ),
      ],
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
      iconSize: 24,
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

class _Dots extends StatelessWidget {
  const _Dots({
    required this.count,
    required this.index,
    required this.color,
    required this.idle,
  });

  final int count;
  final int index;
  final Color color;
  final Color idle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: AppDurations.fast,
            width: i == index ? 18 : 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
            decoration: BoxDecoration(
              color: i == index ? color : idle,
              borderRadius: AppRadius.pillRadius,
            ),
          ),
      ],
    );
  }
}

/// A slim caption naming the rule the app applied — reinforces the "why".
class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.ruleName, required this.color});

  final String ruleName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (ruleName.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(Icons.rule_rounded, size: 15, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              ruleName,
              style: AppTypography.caption.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
