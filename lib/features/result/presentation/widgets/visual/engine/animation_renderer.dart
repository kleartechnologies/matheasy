import 'package:flutter/material.dart';

import '../../../../domain/animation/scene_spec.dart';
import 'engine_palette.dart';
import 'scenes/balance_scale_view.dart';
import 'scenes/data_scene_views.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the scene dispatcher.
///
/// Maps a [SceneObject] to its animated visual-object view, driven by the
/// player's per-beat [progress]. A kind with no painter yet renders nothing, so
/// the equation morph simply stands alone — every category still "works",
/// nothing crashes, and new primitives slot in here without touching the player.
class AnimatedLearningSceneView extends StatelessWidget {
  const AnimatedLearningSceneView({
    super.key,
    required this.scene,
    required this.progress,
    required this.showAnswer,
    required this.palette,
  });

  final SceneObject scene;

  /// The player's per-beat reveal. Passed as an [Animation] (not a bare value)
  /// so each scene animates ONLY its painter, never re-parsing its static
  /// MathText labels (e.g. the balance-scale sides) on every frame.
  final Animation<double> progress;
  final bool showAnswer;
  final EnginePalette palette;

  /// Whether a scene panel should be shown for [kind] (the player uses this to
  /// decide the layout split).
  static bool hasViewFor(SceneObjectKind kind) => switch (kind) {
        SceneObjectKind.balanceScale ||
        SceneObjectKind.parabola ||
        SceneObjectKind.curve ||
        SceneObjectKind.fractionBar ||
        SceneObjectKind.pieChart ||
        SceneObjectKind.barChart ||
        SceneObjectKind.numberLine =>
          true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    switch (scene.kind) {
      case SceneObjectKind.balanceScale:
        return BalanceScaleView(
            scene: scene,
            progress: progress,
            showAnswer: showAnswer,
            palette: palette);
      case SceneObjectKind.parabola:
      case SceneObjectKind.curve:
        return CurveSceneView(
            scene: scene, progress: progress, palette: palette);
      case SceneObjectKind.fractionBar:
        return FractionBarSceneView(
            scene: scene, progress: progress, palette: palette);
      case SceneObjectKind.pieChart:
        return PieSceneView(
            scene: scene, progress: progress, palette: palette);
      case SceneObjectKind.barChart:
        return BarChartSceneView(
            scene: scene, progress: progress, palette: palette);
      case SceneObjectKind.numberLine:
        return NumberLineSceneView(
            scene: scene, progress: progress, palette: palette);
      case SceneObjectKind.areaModel:
      case SceneObjectKind.tangent:
      case SceneObjectKind.riemann:
      case SceneObjectKind.unitCircle:
      case SceneObjectKind.treeDiagram:
      case SceneObjectKind.matrixGrid:
      case SceneObjectKind.vectors:
      case SceneObjectKind.none:
        return const SizedBox.shrink();
    }
  }
}
