import 'package:flutter/material.dart';

import '../../../../core/animations/app_transitions.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/result_models.dart';
import '../widgets/math_text.dart';
import '../widgets/result_empty.dart';

/// Tab 2 — the same solution explained in three registers (Simple / Teacher /
/// Exam), switchable with a segmented control and animated content.
class ExplainTab extends StatefulWidget {
  const ExplainTab({
    super.key,
    required this.explanations,
    required this.onAskMatheasy,
  });

  final List<Explanation> explanations;
  final VoidCallback onAskMatheasy;

  @override
  State<ExplainTab> createState() => _ExplainTabState();
}

class _ExplainTabState extends State<ExplainTab> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.explanations.isEmpty) {
      return const ResultEmpty(
        message: 'No explanation yet — Matheasy is still thinking about the best '
            'way to teach this.',
      );
    }

    final explanation = widget.explanations[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedControl(
          selectedIndex: _index,
          onChanged: (i) => setState(() => _index = i),
          items: [
            for (final e in widget.explanations)
              SegmentItem(label: e.mode.label, icon: e.mode.icon),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AnimatedSwitcher(
          duration: AppDurations.medium,
          transitionBuilder: AppTransitions.fadeThrough,
          child: _Content(
            key: ValueKey(_index),
            explanation: explanation,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SecondaryButton(
          label: 'Still stuck? Ask Matheasy',
          icon: Icons.smart_toy_rounded,
          onPressed: widget.onAskMatheasy,
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({super.key, required this.explanation});

  final Explanation explanation;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isExam = explanation.mode == ExplanationMode.exam;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MatheasyBubble(text: explanation.body),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < explanation.points.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xxs),
                      child: Icon(Icons.check_circle_rounded,
                          size: 18, color: AppColors.success),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: isExam
                          ? MathText(
                              explanation.points[i],
                              style: AppTypography.bodyMedium
                                  .copyWith(color: colors.textPrimary),
                            )
                          : Text(
                              explanation.points[i],
                              style: AppTypography.bodyMedium
                                  .copyWith(color: colors.textPrimary),
                            ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
