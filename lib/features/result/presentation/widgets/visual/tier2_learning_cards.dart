import 'package:flutter/material.dart';

import '../../../../../core/animations/app_transitions.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/widgets/widgets.dart';
import '../../../domain/visual_models.dart';
import 'visual_shared_widgets.dart';

/// Tier 2 — interactive learning cards, for concept-heavy domains
/// (trigonometry, statistics, probability, matrices, vectors, advanced
/// algebra). Every step is an expandable card: the transformation stays
/// visible, tapping reveals the why, a hint and Ask Numi.
class Tier2LearningCards extends StatelessWidget {
  const Tier2LearningCards({
    super.key,
    required this.visual,
    required this.onAskNumi,
  });

  final VisualSolution visual;

  /// Called with the tapped step's index when the student asks Numi.
  final ValueChanged<int> onAskNumi;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final steps = visual.steps;
    final concept = visual.concept;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NumiBubble(text: visual.intro),
        const SizedBox(height: AppSpacing.lg),
        if (concept != null) ...[
          VisualConceptView(concept: concept),
          const SizedBox(height: AppSpacing.lg),
        ],
        for (var i = 0; i < steps.length; i++)
          _staggered(
            reduceMotion: reduceMotion,
            order: i,
            child: VisualStepCard(
              step: steps[i],
              number: i + 1,
              defaultExpanded: i == 0,
              onAskNumi: () => onAskNumi(i),
            ),
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

  /// Staggered entrance matching the Solution tab; skipped for reduced motion.
  Widget _staggered({
    required bool reduceMotion,
    required int order,
    required Widget child,
  }) {
    if (reduceMotion) return child;
    return AppTransitions.slideUp(
      delay: Duration(milliseconds: (order * 60).clamp(0, 300)),
      child: child,
    );
  }
}
