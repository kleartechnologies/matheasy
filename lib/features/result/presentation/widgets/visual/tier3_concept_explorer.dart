import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/visual_models.dart';
import 'visual_shared_widgets.dart';

/// Tier 3 — the Visual Concept Explorer, for domains best understood through
/// a drawing (geometry, functions, graphs, calculus, university math). An
/// explorable canvas (pinch-zoom, pan) renders the AI's visualization
/// metadata, followed by the step cards that explain the concept.
class Tier3ConceptExplorer extends StatelessWidget {
  const Tier3ConceptExplorer({
    super.key,
    required this.visual,
    required this.onAskMatheasy,
  });

  final VisualSolution visual;

  /// Called with the tapped step's index when the student asks Matheasy.
  final ValueChanged<int> onAskMatheasy;

  @override
  Widget build(BuildContext context) {
    final concept = visual.concept;
    final steps = visual.steps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(text: visual.intro),
        const SizedBox(height: AppSpacing.lg),
        if (concept != null) ...[
          VisualConceptView(concept: concept),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (var i = 0; i < steps.length; i++)
          VisualStepCard(
            step: steps[i],
            number: i + 1,
            defaultExpanded: i == 0,
            onAskMatheasy: () => onAskMatheasy(i),
          ),
        if (visual.explanation != null) ...[
          const SizedBox(height: AppSpacing.xs),
          VisualKeyIdeasCard(explanation: visual.explanation!),
        ],
        if (visual.method != null) ...[
          const SizedBox(height: AppSpacing.md),
          VisualMethodCard(method: visual.method!),
        ],
      ],
    );
  }
}
