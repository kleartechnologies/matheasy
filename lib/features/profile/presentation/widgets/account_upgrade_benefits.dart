import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../auth/presentation/widgets/auth_benefit_row.dart';

/// The account-upgrade value proposition, shared by the profile guest card and
/// the upgrade sheet so the copy can never drift between the two surfaces.
///
/// Deliberately never mentions Premium or subscriptions.
class AccountUpgradeBenefits extends StatelessWidget {
  const AccountUpgradeBenefits({super.key, this.spacing = AppSpacing.md});

  /// Vertical gap between benefit rows.
  final double spacing;

  static const List<AuthBenefitRow> _rows = [
    AuthBenefitRow(
      icon: Icons.cloud_done_rounded,
      color: AppColors.primary,
      title: 'Preserve your progress',
      subtitle: 'Keep your XP, streak and achievements.',
    ),
    AuthBenefitRow(
      icon: Icons.sync_rounded,
      color: AppColors.secondary,
      title: 'Sync future data',
      subtitle: 'Pick up on any device once sync arrives.',
    ),
    AuthBenefitRow(
      icon: Icons.lock_open_rounded,
      color: AppColors.success,
      title: 'Unlock future features',
      subtitle: 'Be first to try new tools as they launch.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _rows.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          _rows[i],
        ],
      ],
    );
  }
}
