import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/difficulty_preference.dart';

/// A stacked single-select for the practice [DifficultyPreference], showing each
/// option's icon, label and description with an animated selection state.
class DifficultySelector extends StatelessWidget {
  const DifficultySelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final DifficultyPreference selected;
  final ValueChanged<DifficultyPreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final option in DifficultyPreference.values) ...[
          if (option != DifficultyPreference.values.first)
            const SizedBox(height: AppSpacing.md),
          _DifficultyCard(
            option: option,
            selected: option == selected,
            onTap: () => onChanged(option),
          ),
        ],
      ],
    );
  }
}

class _DifficultyCard extends StatelessWidget {
  const _DifficultyCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final DifficultyPreference option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The emerald that stays legible as a foreground on the active surface —
    // the identity emerald is 2.97:1 and is brand art only.
    final accent = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryDark;
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.label}. ${option.description}',
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        elevated: !selected,
        color: selected ? colors.primaryContainer : colors.surface,
        border: Border.all(
          color: selected ? accent : colors.border,
          width: selected ? 2 : 1.5,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.14)
                    : colors.surfaceMuted,
                borderRadius: AppRadius.smRadius,
              ),
              child: Icon(
                option.icon,
                size: 23,
                color: selected ? accent : colors.textSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: AppTypography.title.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    option.description,
                    style: AppTypography.bodySmall
                        .copyWith(color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
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
      // A filled control carrying a white check — the interactive emerald, so
      // the check clears AA (4.78:1) in both themes.
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryAction : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.primaryAction : context.colors.textMuted,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: AppColors.white)
          : null,
    );
  }
}
