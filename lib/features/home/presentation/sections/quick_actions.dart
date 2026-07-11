import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../practice/presentation/practice_visual_screen.dart'
    show PracticeVisualArgs;
import '../../../subscription/application/subscription_controller.dart';
import '../../../subscription/domain/paywall_trigger.dart';

/// 2×2 grid of the primary Home actions: the top row is the two ways to enter a
/// problem (**Scan · Type**), the bottom row the two ways to learn from it
/// (**Visual Learning · Practice**). Ask Matheasy stays one tap away in the nav.
class QuickActions extends ConsumerWidget {
  const QuickActions({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = <_ActionData>[
      _ActionData(
        icon: Icons.center_focus_strong_rounded,
        label: 'Scan Question',
        color: AppColors.primary,
        onTap: () => context.push(AppRoutes.scan),
      ),
      _ActionData(
        icon: Icons.keyboard_rounded,
        label: 'Type Problem',
        color: AppColors.secondary,
        onTap: () => context.push(AppRoutes.manualInput),
      ),
      _ActionData(
        icon: Icons.auto_awesome_rounded,
        label: 'Visual Learning',
        color: AppColors.accentCoral,
        onTap: () => _openVisualLearning(context, ref),
      ),
      _ActionData(
        icon: Icons.fitness_center_rounded,
        label: 'Practice',
        color: AppColors.accentAmber,
        onTap: () => context.go(AppRoutes.practice),
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

  /// Opens the flagship Visual Learning experience — a sample step-by-step
  /// walkthrough for Pro learners, or the Visual Learning paywall for free
  /// users (so the flagship is discoverable within a tap of Home).
  void _openVisualLearning(BuildContext context, WidgetRef ref) {
    if (ref.read(isProProvider)) {
      context.push(
        AppRoutes.practiceVisual,
        extra: const PracticeVisualArgs(
          latex: r'2x^2 - 8 = 0',
          topicLabel: 'Algebra',
          answerLatex: r'x = \pm 2',
        ),
      );
    } else {
      context.push(AppRoutes.paywall, extra: PaywallTrigger.visualLearning);
    }
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
                  .copyWith(color: context.colors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
