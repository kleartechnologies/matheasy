import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';

/// A selectable row used by the onboarding question pages. Works for both
/// single- and multi-select; composes [AppCard] + design tokens so it inherits
/// press feedback, elevation and dark-mode support.
class OnboardingOptionTile extends StatelessWidget {
  const OnboardingOptionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailingText,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? trailingText;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: AppCard(
        onTap: onTap,
        elevated: !selected,
        color: selected ? colors.primaryContainer : colors.surface,
        border: Border.all(
          color: selected ? AppColors.primary : colors.border,
          width: selected ? 2 : 1.5,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.14)
                    : colors.surfaceMuted,
                borderRadius: AppRadius.smRadius,
              ),
              child: Icon(
                icon,
                size: 23,
                color: selected ? AppColors.primary : colors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: AppTypography.title.copyWith(
                  color:
                      selected ? colors.onPrimaryContainer : colors.textPrimary,
                ),
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText!,
                style: AppTypography.label.copyWith(color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            _SelectionDot(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      curve: AppCurves.standard,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: selected ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primary : context.colors.textTertiary,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: AppColors.white)
          : null,
    );
  }
}
