import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../result/domain/visual_models.dart';
import '../../../result/presentation/widgets/visual/concept_painter.dart';
import '../../domain/practice_figure.dart';

/// Renders a [PracticeFigure]'s labelled geometry figure on-device, by
/// translating it into a [VisualConcept] and drawing it with the Stage-2
/// [ConceptPainter]. It uses exactly the label-key convention the painter draws
/// — polygon `v{i}`/`a{i}`/`s{i}`, unit circle `angle` — so the figure's
/// measurements actually appear. No assets, no network.
class PracticeFigureView extends StatelessWidget {
  const PracticeFigureView({super.key, required this.figure});

  final PracticeFigure figure;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The figure is drawn over a card, so the stroke needs the emerald that
    // survives the current theme — the identity emerald is 2.97:1 on white.
    final stroke =
        context.isDark ? AppColors.primaryLight : AppColors.primaryDark;
    final palette = ConceptPalette(
      grid: colors.divider,
      axis: colors.textMuted,
      stroke: stroke,
      fill: stroke.withValues(alpha: 0.16),
      accent: AppColors.warning,
      textColor: colors.textPrimary,
    );
    // The figure is described in words for screen-reader users; the canvas
    // itself is excluded from semantics (it has none to offer).
    return Semantics(
      image: true,
      label: figure.semanticsLabel,
      child: ExcludeSemantics(
        child: AspectRatio(
          aspectRatio: 3 / 2,
          child: CustomPaint(
            size: Size.infinite,
            painter:
                ConceptPainter(concept: _toConcept(figure), palette: palette),
          ),
        ),
      ),
    );
  }

  /// Maps a [PracticeFigure] onto the painter's [VisualConcept], populating the
  /// label keys Stage 2 draws so the measurements render.
  static VisualConcept _toConcept(PracticeFigure f) {
    switch (f.kind) {
      case PracticeFigureKind.polygon:
        final labels = <String, String>{};
        final params = <String, double>{};
        for (var i = 0; i < f.vertices.length; i++) {
          _put(labels, 'v$i', f.vertexLabels, i);
          _put(labels, 'a$i', f.angleLabels, i);
          _put(labels, 's$i', f.sideLabels, i);
        }
        for (final i in f.rightAngleVertices) {
          params['rightAngle$i'] = 1;
        }
        f.tickEdges.forEach((edge, count) => params['tick$edge'] = count.toDouble());
        return VisualConcept(
          kind: VisualConceptKind.geometryShape,
          caption: f.semanticsLabel,
          points: [for (final p in f.vertices) VisualPoint(p.x, p.y)],
          labels: labels,
          params: params,
        );
      case PracticeFigureKind.circle:
        return VisualConcept(
          kind: VisualConceptKind.circle,
          caption: f.semanticsLabel,
          labels: f.circleLabel == null ? const {} : {'measure': f.circleLabel!},
          params: f.circleShowDiameter ? const {'diameter': 1} : const {},
        );
      case PracticeFigureKind.straightLineAngles:
        return VisualConcept(
          kind: VisualConceptKind.straightLineAngles,
          caption: f.semanticsLabel,
          points: [for (final p in f.vertices) VisualPoint(p.x, p.y)],
          labels:
              f.lineGivenLabel == null ? const {} : {'angle': f.lineGivenLabel!},
        );
    }
  }

  static void _put(Map<String, String> m, String key, List<String> src, int i) {
    if (i < src.length && src[i].isNotEmpty) m[key] = src[i];
  }
}
