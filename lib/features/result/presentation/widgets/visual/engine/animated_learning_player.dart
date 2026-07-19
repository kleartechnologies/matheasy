import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../../core/animations/particle_field.dart';
import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../../../core/services/haptics_service.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/theme/app_durations.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../../../core/widgets/widgets.dart';
import '../../../../domain/animation/animation_script.dart';
import '../visual_shared_widgets.dart';
import 'animation_renderer.dart';
import 'engine_palette.dart';
import 'equation_morph_view.dart';
import 'learning_timeline.dart';
import 'universal_control_bar.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the shared player shell.
///
/// The one player for EVERY topic: it sequences an [AnimationScript], playing
/// each beat's symbol morph (and its visual object, when the category has one),
/// under a named learning timeline and the universal control bar (speed, scrub,
/// prev/next, replay). Generalized from the geometry player: same autoplay,
/// reduced-motion discipline and step-aware semantics — now scene-agnostic.
///
/// It performs NO math: it only sequences and animates the pre-verified script.
class AnimatedLearningPlayer extends StatefulWidget {
  const AnimatedLearningPlayer({
    super.key,
    required this.script,
    required this.onAskMatheasy,
  });

  final AnimationScript script;

  /// Called with the active beat index when the student asks Matheasy.
  final ValueChanged<int> onAskMatheasy;

  @override
  State<AnimatedLearningPlayer> createState() => _AnimatedLearningPlayerState();
}

class _AnimatedLearningPlayerState extends State<AnimatedLearningPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: AppDurations.morph,
  );

  int _index = 0;
  bool _playing = false;
  bool _decidedAutoplay = false;
  PlaybackSpeed _speed = PlaybackSpeed.normal;
  Timer? _timer;

  List<AnimationStep> get _steps => widget.script.steps;
  AnimationStep get _step => _steps[_index];
  bool get _isLast => _index >= _steps.length - 1;

  Duration _scaled(Duration base) =>
      Duration(milliseconds: (base.inMilliseconds * _speed.durationScale).round());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!_decidedAutoplay) {
      _decidedAutoplay = true;
      _entrance.duration = _scaled(AppDurations.morph);
      if (reduceMotion) {
        _entrance.value = 1;
      } else {
        _entrance.forward(from: 0);
        if (_steps.length > 1) _play();
      }
      return;
    }
    // Reduce Motion switched on mid-play → stop everything at its resting state.
    if (reduceMotion) {
      _pause();
      _entrance.value = 1;
    }
  }

  @override
  void didUpdateWidget(AnimatedLearningPlayer old) {
    super.didUpdateWidget(old);
    if (_index >= _steps.length) {
      _index = _steps.isEmpty ? 0 : _steps.length - 1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  void _play() {
    _timer?.cancel();
    _timer = Timer.periodic(_scaled(AppDurations.walkthroughStep), (_) {
      if (_isLast) {
        _pause();
      } else {
        _goTo(_index + 1, fromTimer: true);
      }
    });
    if (mounted) setState(() => _playing = true);
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    if (mounted) setState(() => _playing = false);
  }

  void _goTo(int index, {bool fromTimer = false}) {
    if (!fromTimer) _pause();
    final next = index.clamp(0, _steps.length - 1);
    setState(() => _index = next);
    _fireStepFeedback();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.value = 1;
    } else {
      _entrance
        ..duration = _scaled(AppDurations.morph)
        ..forward(from: 0);
    }
  }

  void _fireStepFeedback() {
    if (MediaQuery.disableAnimationsOf(context)) return;
    final step = _steps[_index];
    if (step.isAnswer) {
      HapticsService.celebrate();
    } else if (step.morph.merged) {
      HapticsService.merge();
    } else {
      HapticsService.step();
    }
  }

  void _cycleSpeed() {
    setState(() => _speed = _speed.next);
    _entrance.duration = _scaled(AppDurations.morph);
    if (_playing) _play(); // restart the timer at the new cadence
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty) return const SizedBox.shrink();
    final script = widget.script;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final palette = EnginePalette.of(context);
    final step = _step;
    final showScene = script.hasScene &&
        AnimatedLearningSceneView.hasViewFor(script.scene.kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(text: script.intro),
        const SizedBox(height: AppSpacing.lg),
        if (showScene) ...[
          _scenePanel(context, palette, reduceMotion, step),
          const SizedBox(height: AppSpacing.md),
        ],
        _morphCard(context, palette, reduceMotion, step),
        const SizedBox(height: AppSpacing.md),
        _stepStrip(context, step),
        const SizedBox(height: AppSpacing.md),
        LearningTimeline(phases: script.phases, current: step.phase),
        const SizedBox(height: AppSpacing.md),
        UniversalControlBar(
          index: _index,
          total: _steps.length,
          playing: _playing,
          reduceMotion: reduceMotion,
          speed: _speed,
          onPrev: _index == 0 ? null : () => _goTo(_index - 1),
          onNext: () => _goTo(_isLast ? 0 : _index + 1),
          onPlayPause: _playing ? _pause : _play,
          onCycleSpeed: _cycleSpeed,
          onSeek: (i) => _goTo(i),
        ),
        const SizedBox(height: AppSpacing.sm),
        AskMatheasyButton(onPressed: () => widget.onAskMatheasy(_index)),
        if (_isLast && script.keyIdeas.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _KeyIdeasCard(ideas: script.keyIdeas),
        ],
        if (script.methodName != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _MethodChip(name: script.methodName!),
        ],
      ],
    );
  }

  Widget _scenePanel(
    BuildContext context,
    EnginePalette palette,
    bool reduceMotion,
    AnimationStep step,
  ) {
    final height = (context.screenHeight * 0.30).clamp(200.0, 320.0);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      clip: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Semantics(
          image: true,
          label: widget.script.scene.caption,
          child: ExcludeSemantics(
            // Each scene animates ONLY its painter internally, so its static
            // LaTeX labels aren't re-parsed every frame — pass the controller.
            child: AnimatedLearningSceneView(
              scene: widget.script.scene,
              progress: reduceMotion
                  ? const AlwaysStoppedAnimation<double>(1)
                  : _entrance,
              showAnswer: step.isAnswer,
              palette: palette,
            ),
          ),
        ),
      ),
    );
  }

  Widget _morphCard(
    BuildContext context,
    EnginePalette palette,
    bool reduceMotion,
    AnimationStep step,
  ) {
    return AppCard(
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.l10n.engineWhatChanged.toUpperCase(),
                    style: AppTypography.label.copyWith(color: palette.muted),
                  ),
                  const Spacer(),
                  if (step.operationLabel != null &&
                      step.operationLabel!.isNotEmpty)
                    VisualOperationChip(label: step.operationLabel!),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // RepaintBoundary so the per-frame morph doesn't dirty the rest of
              // the tab; ClipRect so a stray tall fragment can never overlap the
              // controls below.
              RepaintBoundary(
                child: ClipRect(
                  child: SizedBox(
                    height: 118,
                    width: double.infinity,
                    child: Semantics(
                      liveRegion: true,
                      label: step.semanticLabel,
                      child: ExcludeSemantics(
                        child: EquationMorphView(
                          key: ValueKey(_index),
                          beforeLatex: step.beforeLatex,
                          afterLatex: step.afterLatex,
                          morph: step.morph,
                          progress: _entrance,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (step.isAnswer)
            Positioned.fill(
              child: MathCelebration(active: step.isAnswer, glyphColor: palette.accent),
            ),
        ],
      ),
    );
  }

  Widget _stepStrip(BuildContext context, AnimationStep step) {
    final colors = context.colors;
    return AnimatedSwitcher(
      duration: AppDurations.medium,
      child: Column(
        key: ValueKey(_index),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            step.title,
            style: AppTypography.bodyMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (step.explanation.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              step.explanation,
              style:
                  AppTypography.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyIdeasCard extends StatelessWidget {
  const _KeyIdeasCard({required this.ideas});

  final List<String> ideas;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.visualKeyIdeas,
            style: AppTypography.label.copyWith(color: emerald),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final idea in ideas)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_circle_rounded, size: 18, color: emerald),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      idea,
                      style: AppTypography.bodySmall
                          .copyWith(color: colors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  const _MethodChip({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(Icons.alt_route_rounded, size: 16, color: colors.textMuted),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            name,
            style: AppTypography.caption.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }
}
