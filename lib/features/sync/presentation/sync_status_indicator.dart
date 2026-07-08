import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../application/sync_controller.dart';
import '../domain/sync_state.dart';
import '../domain/sync_status.dart';

/// A compact, animated cloud-sync status: a spinning icon while syncing, a check
/// when synced, an alert on error/offline — with a live-region label so screen
/// readers announce transitions.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key, this.showLabel = true});

  /// When false, only the icon is shown (e.g. as a trailing accessory).
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final colors = context.colors;
    final (icon, color) = _visual(sync.status, colors.textSecondary);
    final label = describeSyncStatus(sync);

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SyncIcon(icon: icon, color: color, spinning: sync.isSyncing),
        if (showLabel) ...[
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ],
    );

    // liveRegion so status changes are announced; excludeSemantics keeps the
    // spinner from being read as a separate node.
    return Semantics(
      liveRegion: true,
      label: 'Cloud sync: $label',
      excludeSemantics: true,
      child: content,
    );
  }

  (IconData, Color) _visual(SyncStatus status, Color neutral) => switch (status) {
        SyncStatus.disabled => (Icons.cloud_off_rounded, neutral),
        SyncStatus.notSynced => (Icons.cloud_queue_rounded, neutral),
        SyncStatus.syncing => (Icons.sync_rounded, AppColors.primary),
        SyncStatus.synced => (Icons.cloud_done_rounded, AppColors.success),
        SyncStatus.offline => (Icons.cloud_off_rounded, AppColors.warning),
        SyncStatus.error => (Icons.error_outline_rounded, AppColors.error),
      };
}

/// A human summary of the current sync state (also the a11y announcement).
String describeSyncStatus(SyncState sync) {
  switch (sync.status) {
    case SyncStatus.disabled:
      return 'Sign in to sync across devices';
    case SyncStatus.notSynced:
      return 'Not synced yet';
    case SyncStatus.syncing:
      return 'Syncing…';
    case SyncStatus.synced:
      final at = sync.lastSyncedAt;
      return at == null ? 'Synced' : 'Synced ${syncTimeAgo(at)}';
    case SyncStatus.offline:
      return 'Offline — will sync later';
    case SyncStatus.error:
      return sync.message ?? 'Sync failed';
  }
}

/// A coarse "time ago" for the last-sync line. Uses the injected [now] so it's
/// testable and free of `DateTime.now()` at call sites.
String syncTimeAgo(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${diff.inDays ~/ 7}w ago';
}

class _SyncIcon extends StatefulWidget {
  const _SyncIcon({
    required this.icon,
    required this.color,
    required this.spinning,
  });

  final IconData icon;
  final Color color;
  final bool spinning;

  @override
  State<_SyncIcon> createState() => _SyncIconState();
}

class _SyncIconState extends State<_SyncIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.verySlow,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = Icon(widget.icon, size: 18, color: widget.color);
    // Respect reduced-motion: show a static icon instead of spinning.
    final spin = widget.spinning && !MediaQuery.disableAnimationsOf(context);
    if (spin && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!spin && _controller.isAnimating) {
      _controller
        ..stop()
        ..reset();
    }
    if (!spin) return icon;
    // Sync icon spins counter-clockwise to read as "refreshing".
    return RotationTransition(
      turns: Tween<double>(begin: 1, end: 0).animate(_controller),
      child: icon,
    );
  }
}
