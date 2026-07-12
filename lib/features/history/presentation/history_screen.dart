import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../application/history_controller.dart';
import 'widgets/history_tile.dart';

/// The full solved-problem history — every cached solution, most-recent-first.
///
/// Tapping a row re-opens the complete result (answer, steps, methods, graph)
/// from the local cache: no `solve()` call, no scan charge, works offline.
/// Deleting a row or clearing all is the user's on-device data control.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyControllerProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded),
          iconSize: 28,
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('History'),
        actions: [
          if (entries.isNotEmpty)
            TextButton(
              onPressed: () => _confirmClear(context, ref),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: entries.isEmpty
          ? EmptyState(
              title: 'No history yet',
              message:
                  'Problems you solve appear here — tap any to re-open the full '
                  'solution instantly, even offline.',
              actionLabel: 'Scan a problem',
              onAction: () => context.push(AppRoutes.scan),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.md,
                AppSpacing.screenH,
                AppSpacing.xxl,
              ),
              itemCount: entries.length,
              separatorBuilder: (_, _) =>
                  const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Dismissible(
                  key: ValueKey(entry.canonicalKey),
                  direction: DismissDirection.endToStart,
                  background: _DeleteBackground(),
                  onDismissed: (_) => ref
                      .read(historyControllerProvider.notifier)
                      .remove(entry.canonicalKey),
                  child: HistoryTile(
                    entry: entry,
                    onTap: () => context.push(
                      AppRoutes.scanResult,
                      extra: entry.equation,
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final confirmed = await AppDialog.show<bool>(
      context,
      icon: Icons.delete_sweep_rounded,
      iconColor: AppColors.error,
      title: 'Clear history?',
      message:
          'This removes every saved solution from this device. It can’t be '
          'undone.',
      primaryLabel: 'Clear all',
      secondaryLabel: 'Cancel',
      destructive: true,
    );
    if (confirmed == true) {
      await ref.read(historyControllerProvider.notifier).clear();
    }
  }
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.14),
        borderRadius: AppRadius.cardRadius,
      ),
      child: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
    );
  }
}
