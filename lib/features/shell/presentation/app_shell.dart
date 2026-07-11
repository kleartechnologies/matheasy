import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/services/app_lifecycle.dart';
import '../../../core/widgets/widgets.dart';
import '../../subscription/application/subscription_service.dart';
import '../../sync/application/sync_controller.dart';

/// Hosts the [StatefulNavigationShell] (the indexed-stack of the 5 tab
/// branches) and the app's custom bottom navigation.
///
/// Because it's a [StatefulShellRoute], each branch keeps its own [Navigator],
/// so scroll position, nested navigation stacks and ephemeral state survive tab
/// switches. Tapping the active tab again pops it back to its root.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _goBranch(int index) {
    navigationShell.goBranch(
      index,
      // Re-tapping the current tab resets it to its initial location.
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the app-lifecycle observer alive for the whole session.
    ref.watch(appLifecycleProvider);
    // Keep the sync engine alive whenever the app shell is shown, so background
    // cloud sync runs for signed-in users (a no-op for guests).
    ref.watch(syncControllerProvider);
    // Keep the RevenueCat billing identity in step with the signed-in user, so
    // purchases attribute to their Firebase uid (a no-op offline / for guests).
    ref.watch(revenueCatIdentitySyncProvider);

    return Scaffold(
      extendBody: true,
      body: navigationShell,
      bottomNavigationBar: AppTabBar(
        currentIndex: navigationShell.currentIndex,
        onTap: _goBranch,
        onScan: () => context.push(AppRoutes.scan),
      ),
    );
  }
}
