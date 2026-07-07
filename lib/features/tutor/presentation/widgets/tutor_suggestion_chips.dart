import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';

/// The interactive quick-reply chips Numi offers under a response ("Explain
/// Simpler", "Give Example", …). Tapping one sends its message back into the
/// conversation. Wraps to multiple lines on narrow screens.
class TutorSuggestionChips extends StatelessWidget {
  const TutorSuggestionChips({
    super.key,
    required this.actions,
    required this.onSelected,
  });

  final List<SuggestionAction> actions;
  final ValueChanged<SuggestionAction> onSelected;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final action in actions)
          FeatureChip(
            label: action.label,
            icon: action.icon,
            onTap: () => onSelected(action),
          ),
      ],
    );
  }
}
