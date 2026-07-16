import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/usage_quota.dart';

/// A compact meter for one metered feature: an icon + label, a remaining/limit
/// readout, and a progress bar. Renders an uncapped "Unlimited" state for Pro.
///
/// Theme-aware (uses `context.colors`) so it sits equally well on Home and the
/// subscription screen in light or dark mode.
class UsageMeter extends StatelessWidget {
  const UsageMeter({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.used,
    required this.limit,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// How many have been consumed.
  final int used;

  /// The cap, or [UsageQuota.unlimited] for an uncapped (Pro) feature.
  final int limit;

  bool get _unlimited => UsageQuota.isUnlimited(limit);
  int get _remaining => _unlimited ? 0 : (limit - used).clamp(0, limit);
  double get _fraction =>
      _unlimited || limit == 0 ? 1 : (used / limit).clamp(0.0, 1.0);
  bool get _depleted => !_unlimited && _remaining == 0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final trailing = _unlimited
        ? 'Unlimited'
        : '$_remaining of $limit left';
    final barColor = _unlimited
        ? AppColors.gold
        : (_depleted ? AppColors.error : color);

    return Semantics(
      label: '$label: $trailing',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: barColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.bodySmall
                      .copyWith(color: colors.textPrimary),
                ),
              ),
              Text(
                trailing,
                style: AppTypography.caption.copyWith(
                  // errorText, not AppColors.error: the "0 of N left" label is
                  // TEXT, and the raw hue is 2.87:1 on the dark surface.
                  color: _depleted ? colors.errorText : colors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.pillRadius,
            child: LinearProgressIndicator(
              value: _fraction,
              minHeight: 6,
              backgroundColor: colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ],
      ),
    );
  }
}
