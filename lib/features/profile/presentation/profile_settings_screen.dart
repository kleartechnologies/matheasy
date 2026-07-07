import 'package:flutter/material.dart';

import '../../../shared/dev/nav_placeholder.dart';

/// Full-screen settings (pushed over the shell). Notification, reminder and
/// account settings arrive in Stage 10.
class ProfileSettingsScreen extends StatelessWidget {
  const ProfileSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const NavPlaceholder(
      title: 'Settings',
      subtitle: 'Notifications, reminders and account settings arrive in '
          'Stage 10.',
      showBack: true,
    );
  }
}
