import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';

/// The two learning hand-offs offered after a wrong answer (Stage 15 ×
/// Stages 6 & 14): ask Matheasy to explain the mistake, or watch a visual
/// walkthrough. Shown only on incorrect answers, below the feedback.
class PracticeMistakeActions extends StatelessWidget {
  const PracticeMistakeActions({
    super.key,
    required this.onAskMatheasy,
    required this.onShowVisual,
  });

  /// Opens Matheasy with the mistake as context ("why is this wrong?").
  final VoidCallback onAskMatheasy;

  /// Opens the Visual Learning walkthrough for the problem (Pro-gated at the
  /// call site — free users are routed to the paywall).
  final VoidCallback onShowVisual;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SecondaryButton(
            label: 'Ask Matheasy why',
            icon: Icons.chat_bubble_outline_rounded,
            size: AppButtonSize.medium,
            onPressed: onAskMatheasy,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: SecondaryButton(
            label: 'Show me visually',
            icon: Icons.auto_awesome_rounded,
            size: AppButtonSize.medium,
            onPressed: onShowVisual,
          ),
        ),
      ],
    );
  }
}
