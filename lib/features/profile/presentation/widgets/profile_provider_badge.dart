import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/indicators/google_g_mark.dart';
import '../../../auth/domain/app_user.dart';

/// A compact pill showing how the learner is signed in (Google / Apple / Guest).
class ProfileProviderBadge extends StatelessWidget {
  const ProfileProviderBadge({super.key, required this.provider});

  final AuthProviderType provider;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final leading = switch (provider) {
      // Google's own multi-colour mark, reproduced verbatim: a third-party
      // brand mark is exempt from our contrast floor (WCAG 1.4.11) — the
      // adjacent label carries the meaning.
      AuthProviderType.google => const GoogleGMark(size: 13),
      AuthProviderType.apple =>
        Icon(Icons.apple, size: 15, color: colors.textPrimary),
      AuthProviderType.email =>
        Icon(Icons.mail_outline_rounded, size: 15, color: colors.textPrimary),
      AuthProviderType.guest =>
        Icon(Icons.person_outline_rounded, size: 15, color: colors.textSecondary),
    };

    return Semantics(
      label: '${provider.label} account',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: AppRadius.pillRadius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: AppSpacing.xs),
            Text(
              '${provider.label} account',
              style: AppTypography.caption.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
