import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';

/// The learning paths offered on a wrong answer.
///
/// While the question is still open (retry): Try Again leads, with Hint /
/// Show Solution / Ask Numi as the supporting ladder — the student always
/// feels there's a way forward. Once the question is resolved, the same
/// widget degrades to the reflective pair (Ask Numi / Show visually).
class PracticeMistakeActions extends StatelessWidget {
  const PracticeMistakeActions({
    super.key,
    required this.onAskMatheasy,
    required this.onShowVisual,
    this.onTryAgain,
    this.onHint,
    this.onShowSolution,
  });

  /// Opens Matheasy with the mistake as context ("why is this wrong?").
  final VoidCallback onAskMatheasy;

  /// Opens the Visual Learning walkthrough for the problem (Pro-gated at the
  /// call site — free users are routed to the paywall).
  final VoidCallback onShowVisual;

  /// Back to answering (retry phase only; null once the question resolved).
  final VoidCallback? onTryAgain;

  /// Escalates the hint ladder (retry phase only).
  final VoidCallback? onHint;

  /// Opens the guided solution (retry phase only — finalizes the question
  /// as incorrect via the give-up path at the call site).
  final VoidCallback? onShowSolution;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        if (onTryAgain case final tryAgain?) ...[
          PrimaryButton(
            label: l10n.practiceTryAgain,
            icon: Icons.refresh_rounded,
            onPressed: tryAgain,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (onHint case final hint?) ...[
                Expanded(
                  child: SecondaryButton(
                    label: l10n.practiceNeedHint,
                    icon: Icons.lightbulb_outline_rounded,
                    size: AppButtonSize.medium,
                    onPressed: hint,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              if (onShowSolution case final showSolution?) ...[
                Expanded(
                  child: SecondaryButton(
                    label: l10n.practiceShowSolution,
                    icon: Icons.school_rounded,
                    size: AppButtonSize.medium,
                    onPressed: showSolution,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: SecondaryButton(
                  label: l10n.practiceAskNumi,
                  icon: Icons.chat_bubble_outline_rounded,
                  size: AppButtonSize.medium,
                  onPressed: onAskMatheasy,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GhostButton(
            label: l10n.practiceShowVisually,
            icon: Icons.auto_awesome_rounded,
            expand: true,
            onPressed: onShowVisual,
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: l10n.practiceAskMatheasyWhy,
                  icon: Icons.chat_bubble_outline_rounded,
                  size: AppButtonSize.medium,
                  onPressed: onAskMatheasy,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SecondaryButton(
                  label: l10n.practiceShowVisually,
                  icon: Icons.auto_awesome_rounded,
                  size: AppButtonSize.medium,
                  onPressed: onShowVisual,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
