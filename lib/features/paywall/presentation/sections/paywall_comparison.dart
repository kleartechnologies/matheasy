import 'package:flutter/material.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../paywall_copy.dart';

/// The Free vs Pro feature comparison table on the paywall.
///
/// Renders on the always-dark paywall surface, so it uses light-on-dark tokens
/// directly rather than `context.colors`.
class PaywallComparison extends StatelessWidget {
  const PaywallComparison({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          const _HeaderRow(),
          const SizedBox(height: AppSpacing.sm),
          Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
          for (final row in PaywallCopy.comparison)
            _FeatureRow(row: row),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final labelStyle = AppTypography.label.copyWith(
      color: Colors.white.withValues(alpha: 0.6),
    );
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(context.l10n.paywallComparePlans, style: labelStyle),
        ),
        Expanded(
          flex: 3,
          child: Text(context.l10n.paywallColumnFree,
              textAlign: TextAlign.center, style: labelStyle),
        ),
        Expanded(
          flex: 3,
          child: Text(
            context.l10n.paywallColumnPro,
            textAlign: TextAlign.center,
            style: AppTypography.label.copyWith(color: AppColors.gold),
          ),
        ),
      ],
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.row});

  final ComparisonRow row;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '${row.label}. Free: ${row.freeLabel ?? (row.freeIncluded ? 'included' : 'not included')}. '
          'Pro: ${row.proLabel}.',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Text(
                row.label,
                style: AppTypography.bodySmall.copyWith(color: AppColors.white),
              ),
            ),
            Expanded(flex: 3, child: Center(child: _freeCell())),
            Expanded(
              flex: 3,
              child: Center(child: _proCell()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _freeCell() {
    if (row.freeLabel != null) {
      return Text(
        row.freeLabel!,
        textAlign: TextAlign.center,
        style: AppTypography.caption.copyWith(
          color: Colors.white.withValues(alpha: 0.7),
        ),
      );
    }
    return row.freeIncluded
        ? Icon(Icons.check_rounded,
            size: 18, color: Colors.white.withValues(alpha: 0.7))
        : Icon(Icons.remove_rounded,
            size: 18, color: Colors.white.withValues(alpha: 0.3));
  }

  Widget _proCell() {
    final isCheck = row.proLabel == 'Included';
    if (isCheck) {
      return const Icon(Icons.check_circle_rounded,
          size: 18, color: AppColors.gold);
    }
    return Text(
      row.proLabel,
      textAlign: TextAlign.center,
      style: AppTypography.caption.copyWith(
        color: AppColors.goldLight,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
