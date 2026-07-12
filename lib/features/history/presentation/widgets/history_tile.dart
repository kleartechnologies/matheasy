import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../result/presentation/widgets/math_text.dart';
import '../../domain/history_entry.dart';

/// A single history row — the rendered problem with when it was solved. Purely
/// presentational: the caller wires [onTap] (re-open) so the tile is reusable on
/// Home and the full History screen.
class HistoryTile extends StatelessWidget {
  const HistoryTile({super.key, required this.entry, this.onTap});

  final HistoryEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 26,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: MathText(
                      entry.equation.latex,
                      style: AppTypography.bodyLarge
                          .copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  relativeTimeLabel(entry.timestamp),
                  style:
                      AppTypography.caption.copyWith(color: colors.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
        ],
      ),
    );
  }
}

/// A compact "time since" label — "Just now", "5m ago", "3h ago", "2d ago", or
/// the date for anything older than a week.
String relativeTimeLabel(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[time.month - 1]} ${time.day}';
}
