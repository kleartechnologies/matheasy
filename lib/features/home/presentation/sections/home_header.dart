import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../profile/application/profile_controller.dart';
import '../../../profile/presentation/widgets/profile_avatar_view.dart';
import '../../domain/home_models.dart';

/// Greeting + streak + the learner's avatar and a quick settings shortcut at the
/// top of Home. Tapping the avatar opens the Profile tab; the gear opens
/// Settings.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, required this.userName, required this.streak});

  final String userName;
  final StreakInfo streak;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final greeting = greetingForHour(DateTime.now().hour);
    final profile = ref.watch(profileControllerProvider);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,',
                style: AppTypography.bodyMedium
                    .copyWith(color: colors.textSecondary),
              ),
              Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headingLarge
                    .copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        _StreakPill(count: streak.current),
        const SizedBox(width: AppSpacing.sm),
        Pressable(
          onTap: () => context.go(AppRoutes.profile),
          borderRadius: const BorderRadius.all(Radius.circular(999)),
          child: Semantics(
            button: true,
            label: 'Open profile',
            child: ProfileAvatarView(
              avatar: profile.editable.avatar,
              initial: profile.initial,
              photoUrl: profile.photoUrl,
              size: 46,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Settings',
          onPressed: () => context.push(AppRoutes.profileSettings),
          icon: Icon(Icons.settings_outlined, color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _StreakPill extends StatelessWidget {
  const _StreakPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.mdRadius,
        boxShadow: context.elevation.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              size: 20, color: AppColors.streak),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$count',
            style:
                AppTypography.title.copyWith(color: context.colors.textPrimary),
          ),
        ],
      ),
    );
  }
}
