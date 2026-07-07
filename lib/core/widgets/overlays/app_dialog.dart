import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';

/// Themed alert dialog with an optional icon, title, message and up to two
/// actions. Use [AppDialog.show] for the common confirm/cancel pattern.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.iconColor = AppColors.primary,
    this.primaryLabel = 'OK',
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.destructive = false,
  });

  final String title;
  final String? message;
  final IconData? icon;
  final Color iconColor;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool destructive;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? message,
    IconData? icon,
    Color iconColor = AppColors.primary,
    String primaryLabel = 'OK',
    VoidCallback? onPrimary,
    String? secondaryLabel,
    VoidCallback? onSecondary,
    bool destructive = false,
  }) {
    return showDialog<T>(
      context: context,
      builder: (_) => AppDialog(
        title: title,
        message: message,
        icon: icon,
        iconColor: iconColor,
        primaryLabel: primaryLabel,
        onPrimary: onPrimary,
        secondaryLabel: secondaryLabel,
        onSecondary: onSecondary,
        destructive: destructive,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.xxl),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: AppRadius.lgRadius,
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headingSmall
                  .copyWith(color: colors.textPrimary),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium
                    .copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                if (secondaryLabel != null) ...[
                  Expanded(
                    child: SecondaryButton(
                      label: secondaryLabel!,
                      onPressed: onSecondary ??
                          () => Navigator.of(context).pop(false),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: PrimaryButton(
                    label: primaryLabel,
                    onPressed:
                        onPrimary ?? () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
