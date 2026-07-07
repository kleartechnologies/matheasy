import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matheasy/shared/mascot/numi_mascot.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';

/// A warm Numi prompt inviting the learner into the tutor.
class NumiMotivationCard extends StatelessWidget {
  const NumiMotivationCard({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: AppRadius.cardRadius,
      ),
      child: Row(
        children: [
          const Floaty(
            amplitude: 5,
            child: NumiMascot(expression: NumiExpression.wave, size: 64),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: AppTypography.bodyMedium.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                GhostButton(
                  label: 'Chat with Numi',
                  icon: Icons.forum_rounded,
                  size: AppButtonSize.small,
                  onPressed: () => context.go(AppRoutes.tutor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
