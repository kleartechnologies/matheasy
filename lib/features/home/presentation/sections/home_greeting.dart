import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/animations/pressable.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../profile/application/profile_controller.dart';
import '../../../profile/presentation/widgets/profile_avatar_view.dart';
import '../../domain/home_models.dart';

/// A calm greeting line + avatar. No streak, no stats — Home is not a dashboard.
class HomeGreeting extends ConsumerWidget {
  const HomeGreeting({super.key, required this.userName});

  final String userName;

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
                style: AppTypography.bodyMedium.copyWith(color: colors.textSecondary),
              ),
              Text(
                userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.headingLarge.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
        Pressable(
          onTap: () => context.go(AppRoutes.profile),
          borderRadius: AppRadius.pillRadius,
          child: Semantics(
            button: true,
            label: 'Open profile',
            child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: ProfileAvatarView(
                  avatar: profile.editable.avatar,
                  initial: profile.initial,
                  photoUrl: profile.photoUrl,
                  size: 44,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
