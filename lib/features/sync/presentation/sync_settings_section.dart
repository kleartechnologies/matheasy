import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../settings/presentation/widgets/settings_section.dart';
import '../../settings/presentation/widgets/settings_tile.dart';
import '../application/sync_controller.dart';
import '../domain/sync_status.dart';
import 'sync_status_indicator.dart';

/// The Settings › Sync section: current status, last-sync time, and a manual
/// "Sync now". Adapts for guests (a sign-in hint) vs. authenticated users.
class SyncSettingsSection extends ConsumerWidget {
  const SyncSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);

    if (!sync.isEnabled) {
      return const SettingsSection(
        title: 'Sync',
        children: [
          SettingsTile(
            icon: Icons.cloud_off_rounded,
            iconColor: AppColors.secondary,
            title: 'Cloud sync',
            subtitle: 'Sign in to back up and sync across your devices',
          ),
        ],
      );
    }

    final busy = sync.status == SyncStatus.syncing;
    final lastSynced = sync.lastSyncedAt;
    final subtitle = lastSynced == null
        ? 'Your progress backs up automatically'
        : 'Last synced ${syncTimeAgo(lastSynced)}';

    return SettingsSection(
      title: 'Sync',
      children: [
        SettingsTile(
          icon: Icons.cloud_done_rounded,
          iconColor: AppColors.success,
          title: 'Cloud sync',
          subtitle: describeSyncStatus(sync),
          trailing: const SyncStatusIndicator(showLabel: false),
        ),
        SettingsTile(
          icon: Icons.sync_rounded,
          title: 'Sync now',
          subtitle: subtitle,
          onTap: busy
              ? null
              : () => unawaited(
                    ref.read(syncControllerProvider.notifier).syncNow(),
                  ),
          trailing: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : null,
        ),
      ],
    );
  }
}
