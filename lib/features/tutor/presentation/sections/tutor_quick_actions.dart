import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/tutor_models.dart';

/// A 2×2 grid of Tutor quick actions (Ask Matheasy, Upload Question, …).
class TutorQuickActions extends StatelessWidget {
  const TutorQuickActions({
    super.key,
    required this.actions,
    required this.onSelected,
  });

  final List<TutorQuickAction> actions;
  final ValueChanged<TutorQuickAction> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Quick actions'),
        const SizedBox(height: AppSpacing.md),
        for (var row = 0; row * 2 < actions.length; row++) ...[
          if (row > 0) const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _ActionTile(action: actions[row * 2], onTap: onSelected)),
              const SizedBox(width: AppSpacing.md),
              if (row * 2 + 1 < actions.length)
                Expanded(
                  child: _ActionTile(
                    action: actions[row * 2 + 1],
                    onTap: onSelected,
                  ),
                )
              else
                const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.onTap});

  final TutorQuickAction action;
  final ValueChanged<TutorQuickAction> onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () => onTap(action),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: action.color.withValues(alpha: 0.14),
              borderRadius: AppRadius.smRadius,
            ),
            child: Icon(action.icon, size: 23, color: action.color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              action.label,
              maxLines: 2,
              style: AppTypography.title.copyWith(
                color: context.colors.textPrimary,
                fontSize: 14.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
