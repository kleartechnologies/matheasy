import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
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

  /// Built per-theme rather than held `const`: the row icon is a foreground, and
  /// no single emerald clears 3:1 on both a light and a dark card.
  List<AuthBenefitRow> _rows(BuildContext context) => [
        AuthBenefitRow(
          icon: Icons.cloud_done_rounded,
          color:
              context.isDark ? AppColors.primaryLight : AppColors.primaryDark,
          title: 'Preserve your progress',
          subtitle: 'Keep your XP, streak and achievements.',
        ),
        const AuthBenefitRow(
          icon: Icons.sync_rounded,
          color: AppColors.secondary,
          title: 'Sync future data',
          subtitle: 'Pick up on any device once sync arrives.',
        ),
        const AuthBenefitRow(
          icon: Icons.lock_open_rounded,
          color: AppColors.accentAmber,
          title: 'Unlock future features',
          subtitle: 'Be first to try new tools as they launch.',
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final rows = _rows(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          rows[i],
        ],
      ],
    );
  }
}
