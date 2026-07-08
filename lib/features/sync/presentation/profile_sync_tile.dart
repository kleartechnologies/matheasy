import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../../settings/presentation/widgets/settings_tile.dart';
import '../application/sync_controller.dart';
import 'sync_status_indicator.dart';

/// A compact cloud-sync status row for the Profile tab — status + last-sync
/// time, tapping through to the full Sync controls in Settings. Only shown for
/// authenticated (cloud-synced) users; the caller omits it for guests.
class ProfileSyncTile extends ConsumerWidget {
  const ProfileSyncTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final lastSynced = sync.lastSyncedAt;
    final subtitle = lastSynced == null
        ? 'Backs up your progress across devices'
        : 'Last synced ${syncTimeAgo(lastSynced)}';

    return SettingsSection(
      children: [
        SettingsTile(
          icon: Icons.cloud_done_rounded,
          iconColor: AppColors.success,
          title: 'Cloud sync',
          subtitle: subtitle,
          trailing: const SyncStatusIndicator(showLabel: false),
          onTap: () => context.push(AppRoutes.profileSettings),
        ),
      ],
    );
  }
}
