import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/services/haptics_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';

/// A settings row with a trailing [AppSwitch]. The whole row is one large tap
/// target and a single `toggled` semantics node.
class SettingsSwitchTile extends StatelessWidget {
  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final bool value;
  final ValueChanged<bool> onChanged;

  void _emit(bool next) {
    HapticsService.selection();
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint = iconColor ?? AppColors.primary;

    return Semantics(
      toggled: value,
      label: subtitle == null ? title : '$title. $subtitle',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _emit(!value),
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: AppRadius.smRadius,
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTypography.title
                            .copyWith(color: colors.textPrimary),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          subtitle!,
                          style: AppTypography.bodySmall
                              .copyWith(color: colors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppSwitch(value: value, onChanged: _emit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
