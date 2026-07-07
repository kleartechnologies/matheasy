import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_routes.dart';
import '../../../core/session/app_session.dart';
import '../../../core/widgets/widgets.dart';
import '../../../shared/dev/nav_placeholder.dart';
import '../../auth/application/auth_controller.dart';

/// Tab root for the Profile branch. Real profile/stats arrive in Stage 10.
///
/// The two "guard demo" buttons flip placeholder session state so the
/// navigation guards can be seen working: signing out redirects to `/auth`,
/// resetting onboarding redirects to `/onboarding`.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NavPlaceholder(
      title: 'Profile',
      subtitle: 'Your stats, achievements and settings — arrive in Stage 10.',
      actions: [
        SecondaryButton(
          label: 'Settings',
          icon: Icons.settings_rounded,
          onPressed: () => context.push(AppRoutes.profileSettings),
        ),
        SecondaryButton(
          label: 'Subscription',
          icon: Icons.workspace_premium_rounded,
          onPressed: () => context.push(AppRoutes.profileSubscription),
        ),
        PrimaryButton(
          label: 'Go Premium',
          icon: Icons.bolt_rounded,
          onPressed: () => context.push(AppRoutes.paywall),
        ),
        GhostButton(
          label: 'Sign out (guard demo)',
          expand: true,
          onPressed: () =>
              unawaited(ref.read(authControllerProvider.notifier).signOut()),
        ),
        GhostButton(
          label: 'Reset onboarding (guard demo)',
          expand: true,
          onPressed: () =>
              ref.read(onboardingControllerProvider.notifier).reset(),
        ),
      ],
    );
  }
}
