import 'package:flutter/material.dart';

import '../../brand/brand.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/app_button.dart';

/// Recoverable error placeholder with the Matheasy brand avatar, a message and
/// an optional retry.
///
/// Deliberately branded rather than alarmed — this is the same calm placeholder
/// shape as [EmptyState]. A red icon would read as *your fault / something
/// broke*; the copy already says what happened, and the state is recoverable.
/// Destructive red stays reserved for actions that actually destroy something.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title = "That didn't go through",
    this.message =
        'Something got in the way just now. Check your connection and give it another try.',
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MatheasyBrandAvatar(size: 120),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.headingSmall
                  .copyWith(color: context.colors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: context.colors.textSecondary),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expand: false,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
