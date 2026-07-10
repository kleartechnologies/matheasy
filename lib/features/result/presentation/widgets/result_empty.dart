import 'package:flutter/material.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A compact, brand-fronted empty state used inside the result tabs (no methods,
/// no explanations, no practice yet).
class ResultEmpty extends StatelessWidget {
  const ResultEmpty({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          const MatheasyBrandAvatar(),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium
                .copyWith(color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
