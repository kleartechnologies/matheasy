import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A single settings row: a tinted leading icon, a title (+ optional subtitle),
/// an optional trailing value/widget, and a chevron when tappable.
///
/// Composes into a [SettingsSection]. Tap target is ≥ 48px tall.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;

  /// Trailing value text shown before the chevron (e.g. the current selection).
  final String? value;

  /// A custom trailing widget; overrides the default chevron.
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tint =
        destructive ? AppColors.error : (iconColor ?? AppColors.primary);
    final titleColor = destructive ? AppColors.error : colors.textPrimary;

    final row = Padding(
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
                  style: AppTypography.title.copyWith(color: titleColor),
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
          if (value != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              value!,
              style: AppTypography.bodyMedium
                  .copyWith(color: colors.textSecondary),
            ),
          ],
          if (trailing != null)
            trailing!
          else if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Semantics(container: true, label: _semanticLabel, child: row);
    }
    return Semantics(
      button: true,
      label: _semanticLabel,
      excludeSemantics: true,
      child: Pressable(onTap: onTap, scale: 0.98, child: row),
    );
  }

  String get _semanticLabel => [title, ?subtitle, ?value].join('. ');
}
