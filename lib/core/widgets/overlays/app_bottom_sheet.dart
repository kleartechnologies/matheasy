import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Themed modal bottom sheet with a drag handle, optional title and safe-area
/// aware content. Use [AppBottomSheet.show] to present any content.
class AppBottomSheet extends StatelessWidget {
  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
  });

  final Widget child;
  final String? title;

  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    String? title,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) => AppBottomSheet(title: title, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.sheetRadius,
      ),
      padding: EdgeInsets.only(bottom: context.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colors.border,
                    borderRadius: AppRadius.pillRadius,
                  ),
                ),
              ),
              if (title != null) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  title!,
                  style: AppTypography.headingSmall
                      .copyWith(color: colors.textPrimary),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
