import 'package:flutter/material.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../animations/floaty.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Full-area loading placeholder. Optionally shows Numi "thinking" for the
/// warmer, on-brand loading moments (solving, generating practice).
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    this.message,
    this.showMascot = false,
  });

  final String? message;
  final bool showMascot;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showMascot)
            const Floaty(
              child: NumiMascot(expression: NumiExpression.thinking),
            )
          else
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: context.colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
