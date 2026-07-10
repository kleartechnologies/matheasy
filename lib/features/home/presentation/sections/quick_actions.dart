import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';

/// 2×2 grid of the primary Home actions.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = <_ActionData>[
      _ActionData(
        icon: Icons.center_focus_strong_rounded,
        label: 'Scan Question',
        color: AppColors.primary,
        onTap: () => context.push(AppRoutes.scan),
      ),
      _ActionData(
        icon: Icons.forum_rounded,
        label: 'Ask Matheasy',
        color: AppColors.secondary,
        onTap: () => context.go(AppRoutes.tutor),
      ),
      _ActionData(
        icon: Icons.fitness_center_rounded,
        label: 'Practice',
        color: AppColors.accentAmber,
        onTap: () => context.go(AppRoutes.practice),
      ),
      _ActionData(
        icon: Icons.functions_rounded,
        label: 'Formula Library',
        color: AppColors.amber,
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Formula Library is coming soon.')),
        ),
      ),
    ];

    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _ActionTile(actions[row * 2])),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _ActionTile(actions[row * 2 + 1])),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionData {
  const _ActionData({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile(this.data);

  final _ActionData data;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: data.onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.14),
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(data.icon, size: 23, color: data.color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              data.label,
              style: AppTypography.title
                  .copyWith(color: context.colors.textPrimary, fontSize: 14.5),
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}
