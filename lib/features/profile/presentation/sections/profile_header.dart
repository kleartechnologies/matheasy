import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/profile_view.dart';
import '../widgets/profile_avatar_view.dart';
import '../widgets/profile_provider_badge.dart';

/// The Profile identity card: avatar, name, email/provider and an edit action.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({super.key, required this.profile, required this.onEdit});

  final ProfileView profile;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final email = profile.email;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProfileAvatarView(
                avatar: profile.editable.avatar,
                initial: profile.initial,
                photoUrl: profile.photoUrl,
                size: 68,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      profile.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.headingMedium
                          .copyWith(color: colors.textPrimary),
                    ),
                    if (email != null && email.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodySmall
                            .copyWith(color: colors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    ProfileProviderBadge(provider: profile.provider),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: 'Edit profile',
            icon: Icons.edit_rounded,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}
