import 'package:flutter/material.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// One selectable pricing card on the (always-dark) paywall.
///
/// Purely presentational — it takes display strings, not domain types — so it
/// renders identically for the free and paid plans and stays trivial to test.
/// The selected card gains a gold ring and a tight gold lift; an optional
/// [badge] flags the recommended plan.
class PaywallPlanCard extends StatelessWidget {
  const PaywallPlanCard({
    super.key,
    required this.title,
    required this.priceString,
    required this.periodLabel,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.badge,
  });

  /// Plan name, e.g. "Annual Pro".
  final String title;

  /// Localized price, e.g. "RM149.99" or "RM0".
  final String priceString;

  /// Period suffix, e.g. "/year", "/month", "forever".
  final String periodLabel;

  /// Optional value line under the price (e.g. "Just RM12.50/mo · Save 37%").
  final String? subtitle;

  /// Optional corner ribbon, e.g. "BEST VALUE".
  final String? badge;

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.gold
        : Colors.white.withValues(alpha: 0.16);
    final semanticsLabel = StringBuffer('$title, $priceString $periodLabel')
      ..write(subtitle == null ? '' : ', $subtitle')
      ..write(badge == null ? '' : ', $badge');

    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: semanticsLabel.toString(),
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        borderRadius: AppRadius.cardRadius,
        child: AnimatedContainer(
          duration: AppDurations.fast,
          curve: AppCurves.standard,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.gold.withValues(alpha: 0.12)
                : Colors.white.withValues(alpha: 0.05),
            borderRadius: AppRadius.cardRadius,
            border: Border.all(color: borderColor, width: selected ? 2 : 1.5),
            // Selection is already carried by the 2px gold ring, the gold-tinted
            // fill and the dot; the shadow only lifts the card off the backdrop.
            // Kept tight and low-alpha so it never reads as a halo.
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              _SelectionDot(selected: selected),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: AppTypography.title
                                .copyWith(color: AppColors.white),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          _Badge(label: badge!),
                        ],
                      ],
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        subtitle!,
                        style: AppTypography.bodySmall.copyWith(
                          color: selected
                              ? AppColors.goldLight
                              : Colors.white.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    priceString,
                    style: AppTypography.headingSmall
                        .copyWith(color: AppColors.white),
                  ),
                  Text(
                    periodLabel,
                    style: AppTypography.caption.copyWith(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectionDot extends StatelessWidget {
  const _SelectionDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppDurations.fast,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.gold : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.gold : Colors.white.withValues(alpha: 0.4),
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 15, color: AppColors.onGold)
          : null,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.goldGradient,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        label,
        style: AppTypography.label.copyWith(color: AppColors.onGold),
      ),
    );
  }
}
