import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/gallery/presentation/gallery_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/paywall/presentation/paywall_screen.dart';
import '../../features/practice/domain/practice_session.dart';
import '../../features/practice/presentation/practice_screen.dart';
import '../../features/practice/presentation/practice_session_screen.dart';
import '../../features/profile/presentation/profile_edit_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/profile_subscription_screen.dart';
import '../../features/progress/presentation/achievements_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/result/presentation/result_screen.dart';
import '../../features/scan/domain/detected_equation.dart';
import '../../features/scan/presentation/scanner_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/tutor/domain/tutor_models.dart';
import '../../features/tutor/presentation/tutor_chat_screen.dart';
import '../../features/tutor/presentation/tutor_screen.dart';
import '../extensions/context_extensions.dart';
import '../session/app_session.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_routes.dart';
import 'route_guard.dart';

/// Root navigator key — sub-routes and full-screen flows push onto this so they
/// display over (and hide) the tab shell.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'root');

/// The application router.
///
/// Built as a Riverpod [Provider] so navigation guards can read live session
/// state and re-run when it changes (via [refreshListenable]). Structure:
///
/// * Top-level flows (`/onboarding`, `/auth`, `/paywall`, `/gallery`) sit on
///   the root navigator.
/// * A [StatefulShellRoute.indexedStack] holds the 5 tab branches
///   (Home, Practice, Scan, Tutor, Profile) — each with its own Navigator so
///   state is preserved across tab switches.
/// * Immersive sub-routes (`/scan/result`, `/practice/session`, `/tutor/chat`,
///   settings, subscription) declare `parentNavigatorKey: rootNavigatorKey` so
///   they push full-screen over the shell.
final Provider<GoRouter> goRouterProvider = Provider<GoRouter>((ref) {
  // Bridge the session providers to a Listenable so redirects re-run on change.
  final refresh = ValueNotifier<int>(0);
  ref
    ..onDispose(refresh.dispose)
    ..listen(authStatusProvider, (_, _) => refresh.value++)
    ..listen(onboardingControllerProvider, (_, _) => refresh.value++)
    ..listen(premiumControllerProvider, (_, _) => refresh.value++);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) => RouteGuard.evaluate(
      matchedLocation: state.matchedLocation,
      uri: state.uri,
      authStatus: ref.read(authStatusProvider),
      onboardingComplete: ref.read(onboardingControllerProvider),
      isPremium: ref.read(premiumControllerProvider),
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: AppRoutes.splashName,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: AppRoutes.onboardingName,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.auth,
        name: AppRoutes.authName,
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: AppRoutes.paywall,
        name: AppRoutes.paywallName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PaywallScreen(),
      ),
      GoRoute(
        path: AppRoutes.gallery,
        name: AppRoutes.galleryName,
        builder: (context, state) => const GalleryScreen(),
      ),
      // Scan is a full-screen route over the shell (the tab bar disappears),
      // launched from the center Scan button — not a tab branch.
      GoRoute(
        path: AppRoutes.scan,
        name: AppRoutes.scanName,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ScannerScreen(),
        routes: [
          GoRoute(
            path: AppRoutes.scanResultSegment,
            name: AppRoutes.scanResultName,
            parentNavigatorKey: rootNavigatorKey,
            builder: (context, state) => ResultScreen(
              equation: state.extra as DetectedEquation?,
            ),
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // Branch 0 — Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: AppRoutes.homeName,
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Branch 1 — Practice
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.practice,
                name: AppRoutes.practiceName,
                builder: (context, state) => const PracticeScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.practiceSessionSegment,
                    name: AppRoutes.practiceSessionName,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => PracticeSessionScreen(
                      request: state.extra as PracticeRequest?,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Branch 2 — Tutor
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.tutor,
                name: AppRoutes.tutorName,
                builder: (context, state) => const TutorScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.tutorChatSegment,
                    name: AppRoutes.tutorChatName,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => TutorChatScreen(
                      launchContext: state.extra as TutorLaunchContext?,
                    ),
                  ),
                ],
              ),
            ],
          ),
          // Branch 3 — Profile
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                name: AppRoutes.profileName,
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.profileSettingsSegment,
                    name: AppRoutes.profileSettingsName,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const SettingsScreen(),
                  ),
                  GoRoute(
                    path: AppRoutes.profileEditSegment,
                    name: AppRoutes.profileEditName,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const ProfileEditScreen(),
                  ),
                  GoRoute(
                    path: AppRoutes.profileSubscriptionSegment,
                    name: AppRoutes.profileSubscriptionName,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) =>
                        const ProfileSubscriptionScreen(),
                  ),
                ],
              ),
            ],
          ),
          // Branch 4 — Progress
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.progress,
                name: AppRoutes.progressName,
                builder: (context, state) => const ProgressScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.progressAchievementsSegment,
                    name: AppRoutes.progressAchievementsName,
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const AchievementsScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => _RouteErrorScreen(error: state.error),
  );
});

class _RouteErrorScreen extends StatelessWidget {
  const _RouteErrorScreen({this.error});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: context.colors.textTertiary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Page not found',
                style: AppTypography.headingSmall
                    .copyWith(color: context.colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                error?.toString() ?? 'Unknown route error',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall
                    .copyWith(color: context.colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
