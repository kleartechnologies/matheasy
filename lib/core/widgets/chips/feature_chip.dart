import 'package:flutter/material.dart';

import '../../animations/pressable.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_durations.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A pill chip used for suggested prompts, filters and quick tags. Supports an
/// optional leading icon and a selected state.
class FeatureChip extends StatelessWidget {
  const FeatureChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final fg = selected ? AppColors.white : AppColors.primary;

    final chip = Pressable(
      onTap: onTap,
      scale: 0.96,
      borderRadius: AppRadius.pillRadius,
      child: AnimatedContainer(
        duration: AppDurations.fast,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : colors.surface,
          borderRadius: AppRadius.pillRadius,
          border: Border.all(
            color: selected ? AppColors.primary : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: AppTypography.caption.copyWith(
                color: fg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    // A tappable chip is a button; a static tag is not. Announce accordingly.
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: chip,
    );
  }
}
