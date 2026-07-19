import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../../../core/extensions/context_extensions.dart';
import '../../../../../../core/localization/l10n_extension.dart';
import '../../../../../../core/services/haptics_service.dart';
import '../../../../../../core/theme/app_colors.dart';
import '../../../../../../core/theme/app_durations.dart';
import '../../../../../../core/theme/app_radius.dart';
import '../../../../../../core/theme/app_spacing.dart';
import '../../../../../../core/theme/app_typography.dart';
import '../../../../domain/animation/animation_script.dart';
import '../../../../domain/animation/scene_spec.dart';
import '../visual_shared_widgets.dart';
import 'animation_renderer.dart';
import 'engine_palette.dart';
import 'equation_morph_view.dart';
import 'universal_control_bar.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the shared player shell (Stage 15.5:
/// the CALM redesign).
///
/// The one player for EVERY topic. The equation is the HERO: it owns the screen,
/// and only the ONE changing term draws the eye. Everything else is deliberately
/// quiet — a small "Step X of Y" with minimal dots up top, a single-sentence
/// explanation that appears AFTER the animation, and a compact control row.
/// No competing scene cards, no big timeline, no celebration, no clutter — the
/// student tracks one transformation, like watching a great teacher at a
/// whiteboard. (A small graph appears only for graph problems, after the
/// equation settles.)
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
    _timer = Timer.periodic(_scaled(AppDurations.engineStep), (_) {
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
    // A single, quiet tick per beat — no celebration during learning.
    if (_steps[_index].morph.merged) {
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
    final sceneProgress = reduceMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : _entrance;

    // The equation owns the screen: a large, plain, centred hero. Graphs appear
    // only for genuine graph problems, small and only once the answer is reached.
    final equationHeight = (context.screenHeight * 0.42).clamp(300.0, 520.0);
    final showEndGraph =
        _isLast && script.hasScene && _isGraphScene(script.scene.kind);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepHeader(index: _index, total: _steps.length),
        const SizedBox(height: AppSpacing.sm),
        // THE HERO — the equation, big and centred, the sole focal point.
        SizedBox(
          height: equationHeight,
          child: RepaintBoundary(
            child: ClipRect(
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
                    fontSize: 40,
                  ),
                ),
              ),
            ),
          ),
        ),
        // One sentence, appearing AFTER the animation settles.
        _Explanation(
          key: ValueKey(_index),
          step: step,
          progress: _entrance,
          reduceMotion: reduceMotion,
        ),
        // The graph (graph problems only) eases in on the answer beat rather
        // than snapping the controls down.
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : AppDurations.medium,
          curve: AppCurves.standard,
          alignment: Alignment.topCenter,
          child: showEndGraph
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _endGraph(context, palette, sceneProgress, step),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: AppSpacing.lg),
        UniversalControlBar(
          index: _index,
          total: _steps.length,
          playing: _playing,
          reduceMotion: reduceMotion,
          speed: _speed,
          compact: true,
          onPrev: _index == 0 ? null : () => _goTo(_index - 1),
          onNext: () => _goTo(_isLast ? 0 : _index + 1),
          onPlayPause: _playing ? _pause : _play,
          onCycleSpeed: _cycleSpeed,
          onSeek: (i) => _goTo(i),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child:
              AskMatheasyButton(onPressed: () => widget.onAskMatheasy(_index)),
        ),
      ],
    );
  }

  bool _isGraphScene(SceneObjectKind kind) =>
      kind == SceneObjectKind.curve || kind == SceneObjectKind.parabola;

  Widget _endGraph(
    BuildContext context,
    EnginePalette palette,
    Animation<double> progress,
    AnimationStep step,
  ) {
    final height = (context.screenHeight * 0.22).clamp(150.0, 240.0);
    return SizedBox(
      height: height,
      child: Semantics(
        image: true,
        label: widget.script.scene.caption,
        child: ExcludeSemantics(
          child: AnimatedLearningSceneView(
            scene: widget.script.scene,
            progress: progress,
            showAnswer: step.isAnswer,
            palette: palette,
          ),
        ),
      ),
    );
  }
}

/// The quiet header: "Step X of Y" with minimal progress dots. Never competes
/// with the equation.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.index, required this.total});

  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    return Semantics(
      label: context.l10n.resultStepOfTotal(index + 1, total),
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(
              context.l10n.resultStepOfTotal(index + 1, total),
              style: AppTypography.label.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.xs),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < total; i++)
                    AnimatedContainer(
                      duration: AppDurations.fast,
                      width: i == index ? 16 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxs),
                      decoration: BoxDecoration(
                        color: i == index ? emerald : colors.border,
                        borderRadius: AppRadius.pillRadius,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The single-sentence explanation. It fades in only AFTER the morph settles, so
/// nothing competes with the equation while it transforms. An optional "Why?"
/// reveals the deeper detail on demand.
class _Explanation extends StatefulWidget {
  const _Explanation({
    super.key,
    required this.step,
    required this.progress,
    required this.reduceMotion,
  });

  final AnimationStep step;
  final Animation<double> progress;
  final bool reduceMotion;

  @override
  State<_Explanation> createState() => _ExplanationState();
}

class _ExplanationState extends State<_Explanation> {
  bool _showWhy = false;

  /// Keep the default to ONE sentence; the rest lives behind "Why?". Handles
  /// Latin ('. ' — a space avoids splitting decimals like 3.5) and the CJK
  /// full stop / marks used by the app's zh/ja locales.
  static String _firstSentence(String s) {
    final t = s.trim();
    var best = -1;
    for (final d in const ['. ', '。', '！', '？']) {
      final i = t.indexOf(d);
      if (i > 0 && (best < 0 || i < best)) best = i;
    }
    return best > 0 ? t.substring(0, best + 1) : t;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final emerald =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final oneLine = _firstSentence(widget.step.explanation);
    final why = widget.step.hint;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (oneLine.isNotEmpty)
          Text(
            oneLine,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        if (why != null && why.isNotEmpty) ...[
          TextButton(
            onPressed: () => setState(() => _showWhy = !_showWhy),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              foregroundColor: emerald,
            ),
            child: Text(context.l10n.engineWhy),
          ),
          AnimatedCrossFade(
            duration: AppDurations.fast,
            crossFadeState: _showWhy
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: Text(
                why,
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: colors.textMuted),
              ),
            ),
          ),
        ],
      ],
    );

    return AnimatedBuilder(
      animation: widget.progress,
      builder: (context, child) {
        // Appear only AFTER the morph completes (its new value settles at 0.75),
        // so nothing competes with the equation while it transforms.
        final o = widget.reduceMotion
            ? 1.0
            : Curves.easeOut
                .transform(((widget.progress.value - 0.8) / 0.2).clamp(0.0, 1.0));
        final hidden = o < 0.99;
        // While invisible it must not be tappable OR focusable (Opacity alone
        // blocks neither) — else a blind tap could pre-expand "Why?".
        return IgnorePointer(
          ignoring: hidden,
          child: Opacity(
            opacity: o,
            child: hidden ? ExcludeSemantics(child: child) : child,
          ),
        );
      },
      child: content,
    );
  }
}
