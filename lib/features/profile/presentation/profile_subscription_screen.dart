import 'package:flutter/material.dart';

import '../../../shared/dev/nav_placeholder.dart';

/// Full-screen subscription management (pushed over the shell). Wired to
/// RevenueCat entitlements in Stage 11.
class ProfileSubscriptionScreen extends StatelessWidget {
  const ProfileSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const NavPlaceholder(
      title: 'Subscription',
      subtitle: 'Manage your plan and entitlements — wired to RevenueCat in '
          'Stage 11.',
      showBack: true,
    );
  }
}
