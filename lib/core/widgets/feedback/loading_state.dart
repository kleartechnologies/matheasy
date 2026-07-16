import 'package:flutter/material.dart';

import '../../animations/floaty.dart';
import '../../brand/brand.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Full-area loading placeholder. Optionally shows the Matheasy brand avatar
/// for the warmer, on-brand loading moments (solving, generating practice).
class LoadingState extends StatelessWidget {
  const LoadingState({
    super.key,
    this.message,
    this.showBrand = false,
  });

  final String? message;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showBrand)
            const Floaty(
              child: MatheasyBrandAvatar(),
            )
          else
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                // A meaning-bearing graphic on the page background: the
                // identity tone is 2.97:1 there and would fail the 3:1 floor.
                valueColor: AlwaysStoppedAnimation(
                  context.isDark
                      ? AppColors.primaryLight
                      : AppColors.primaryDark,
                ),
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
