import 'package:flutter/material.dart';

import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../result/domain/visual_models.dart';
import '../../../result/presentation/widgets/visual/concept_painter.dart';

/// The drawing beside Numi's explanation (spec Part 9).
///
/// Painted by the same [ConceptPainter] the Visual tab uses, so a parabola in
/// chat is the same parabola as everywhere else — a student never has to learn
/// two visual languages. Compact and non-interactive: this is an illustration
/// inside a sentence, not a canvas to explore.
///
/// It draws ITSELF: the numbers arrive final, but the picture animates from
/// nothing to them, so the student watches the area sweep out, the bar fill,
/// the angle open. That is the difference between showing an answer and showing
/// the maths happening.
class TutorSketchView extends StatelessWidget {
  const TutorSketchView(this.sketch, {super.key});

  final VisualConcept sketch;

  @override
  Widget build(BuildContext context) {
    final palette = ConceptPalette.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      image: true,
      label: sketch.caption,
      child: ExcludeSemantics(
        child: ClipRRect(
          borderRadius: AppRadius.mdRadius,
          child: AspectRatio(
            // Wider than the Visual tab's 3:2 — a chat bubble is narrow, and a
            // tall drawing would push the words that explain it off screen.
            aspectRatio: 16 / 9,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
              duration: reduceMotion ? Duration.zero : AppDurations.verySlow,
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: ConceptPainter(
                    concept: sketchAtProgress(sketch, t),
                    palette: palette,
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

/// The sketch part-way through drawing itself, at progress [t] in `0..1`.
///
/// Only the parameter that carries the *meaning* is tweened, and only where
/// there is a meaning to tween: an area grows from its lower bound, a fraction
/// bar fills a cell at a time, an angle opens from zero. A line or a parabola
/// has no such quantity — a half-drawn curve is just a shorter curve, which
/// says something false — so those simply appear.
VisualConcept sketchAtProgress(VisualConcept sketch, double t) {
  final progress = t.clamp(0.0, 1.0);
  if (progress >= 1) return sketch;

  double lerp(double from, double to) => from + (to - from) * progress;

  switch (sketch.kind) {
    case VisualConceptKind.areaUnderCurve:
      final from = sketch.param('from');
      return _withParams(sketch, {'to': lerp(from, sketch.param('to'))});
    case VisualConceptKind.fractionBar:
      return _withParams(sketch, {'numerator': lerp(0, sketch.param('numerator'))});
    case VisualConceptKind.unitCircle:
      return _withParams(
        sketch,
        {'angleDegrees': lerp(0, sketch.param('angleDegrees'))},
      );
    case VisualConceptKind.linearGraph:
    case VisualConceptKind.parabolaGraph:
    case VisualConceptKind.numberLine:
    case VisualConceptKind.barChart:
    case VisualConceptKind.geometryShape:
    case VisualConceptKind.circle:
    case VisualConceptKind.straightLineAngles:
    case VisualConceptKind.generic:
      return sketch;
  }
}

VisualConcept _withParams(VisualConcept sketch, Map<String, double> changes) =>
    VisualConcept(
      kind: sketch.kind,
      caption: sketch.caption,
      params: {...sketch.params, ...changes},
      labels: sketch.labels,
      points: sketch.points,
    );
