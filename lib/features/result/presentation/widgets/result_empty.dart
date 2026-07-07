import 'package:flutter/material.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A compact, Numi-fronted empty state used inside the result tabs (no methods,
/// no explanations, no practice yet).
class ResultEmpty extends StatelessWidget {
  const ResultEmpty({
    super.key,
    required this.message,
    this.expression = NumiExpression.thinking,
  });

  final String message;
  final NumiExpression expression;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          NumiMascot(expression: expression),
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
