import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/widgets.dart';

/// The persistent, floating bottom action bar for the result screen.
/// Fades from transparent into the background and respects the safe area.
class ResultActionBar extends StatelessWidget {
  const ResultActionBar({
    super.key,
    required this.saved,
    required this.onAskMatheasy,
    required this.onGeneratePractice,
    required this.onToggleSave,
  });

  final bool saved;
  final VoidCallback onAskMatheasy;
  final VoidCallback onGeneratePractice;
  final VoidCallback onToggleSave;

  @override
  Widget build(BuildContext context) {
    final bg = context.colors.background;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.screenH,
        AppSpacing.md,
        AppSpacing.screenH,
        AppSpacing.md + context.viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [bg.withValues(alpha: 0), bg],
          stops: const [0, 0.4],
        ),
      ),
      child: Row(
        children: [
          // Balanced paired CTAs — the secondary action stays fully readable.
          Expanded(
            child: SecondaryButton(
              label: 'Ask Matheasy',
              icon: Icons.smart_toy_rounded,
              onPressed: onAskMatheasy,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: PrimaryButton(
              label: 'Practice',
              icon: Icons.auto_awesome_rounded,
              onPressed: onGeneratePractice,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _SaveButton(saved: saved, onTap: onToggleSave),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.onTap});

  final bool saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: saved ? 'Remove from saved' : 'Save solution',
      child: Pressable(
        onTap: onTap,
        borderRadius: AppRadius.pillRadius,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            // Saved fills behind a white bookmark → the interactive emerald.
            color: saved ? AppColors.primaryAction : colors.surface,
            shape: BoxShape.circle,
            border: Border.all(
              color: saved ? AppColors.primaryAction : colors.border,
            ),
            boxShadow: context.elevation.card,
          ),
          child: Icon(
            saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            color: saved ? AppColors.white : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
