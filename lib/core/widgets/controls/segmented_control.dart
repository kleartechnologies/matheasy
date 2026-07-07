import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../services/haptics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_durations.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One choice in a [SegmentedControl].
class SegmentItem {
  const SegmentItem({required this.label, this.icon});
  final String label;
  final IconData? icon;
}

/// An animated segmented control with a sliding selection pill. Used for the
/// result tabs and the explanation-mode switch. Theme-aware and haptic.
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  }) : assert(items.length > 0, 'SegmentedControl needs at least one item');

  final List<SegmentItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = 5.0;
        final segmentWidth =
            (constraints.maxWidth - padding * 2) / items.length;
        return Container(
          height: 46,
          padding: const EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: AppRadius.mdRadius,
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: AppDurations.medium,
                curve: AppCurves.standard,
                left: segmentWidth * selectedIndex,
                top: 0,
                bottom: 0,
                width: segmentWidth,
                child: Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadius.smRadius,
                    boxShadow: context.elevation.card,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: _Segment(
                        item: items[i],
                        selected: i == selectedIndex,
                        onTap: () {
                          if (i != selectedIndex) {
                            HapticsService.selection();
                            onChanged(i);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final SegmentItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : context.colors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.icon != null) ...[
                Icon(item.icon, size: 16, color: color),
                const SizedBox(width: AppSpacing.xs),
              ],
              Flexible(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
