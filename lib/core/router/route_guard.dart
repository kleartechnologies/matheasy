import '../session/app_session.dart';
import 'app_routes.dart';
import 'deep_link_parser.dart';

/// Pure navigation-guard logic, kept free of Riverpod/BuildContext so it can be
/// unit-tested in isolation. The router wires live session state into
/// [evaluate]; the ordering here is the app's redirect policy.
///
/// STAGE 1: onboarding + auth guards are active against placeholder session
/// state; the premium guard is scaffolded ([premiumRoutes] is empty until
/// premium-only destinations exist).
class RouteGuard {
  const RouteGuard._();

  /// Routes reachable regardless of auth (dev tooling, legal, conversion).
  static const Set<String> alwaysAllowed = {
    AppRoutes.gallery,
    AppRoutes.paywall,
  };

  /// Locations that require the `premium` entitlement. Populated as premium
  /// features ship.
  static const Set<String> premiumRoutes = {};

  static bool _requiresPremium(String location) =>
      premiumRoutes.contains(location);

  /// Returns the location to redirect to, or `null` to allow the navigation.
  ///
  /// Takes primitives (not `GoRouterState`) so it stays trivially unit-testable
  /// and free of go_router coupling.
  static String? evaluate({
    required String matchedLocation,
    required Uri uri,
    required AuthStatus authStatus,
    required bool onboardingComplete,
    required bool isPremium,
  }) {
    // 0) External deep links (matheasy:// or https://matheasy.app) resolve to
    //    an in-app location before the session gates run.
    final deepLinkTarget = DeepLinkParser.resolve(uri);
    if (deepLinkTarget != null && deepLinkTarget != matchedLocation) {
      return deepLinkTarget;
    }

    final location = matchedLocation;

    // 1) The splash screen owns its own hand-off; never redirect it.
    if (location == AppRoutes.splash) return null;

    final atOnboarding = location == AppRoutes.onboarding;
    final atAuth = location == AppRoutes.auth;

    // 2) Onboarding gate.
    if (!onboardingComplete && !atOnboarding) {
      return AppRoutes.onboarding;
    }

    // 3) Auth gate — unauthenticated users are sent to /auth, except for the
    //    always-allowed routes and the auth screen itself.
    if (onboardingComplete &&
        authStatus == AuthStatus.unauthenticated &&
        !atAuth &&
        !alwaysAllowed.contains(location)) {
      return AppRoutes.auth;
    }

    // 4) Once the session is ready, bounce away from onboarding/auth.
    final sessionReady =
        onboardingComplete && authStatus == AuthStatus.authenticated;
    if (sessionReady && (atOnboarding || atAuth)) {
      return AppRoutes.home;
    }

    // 5) Premium gate (scaffolded).
    if (_requiresPremium(location) && !isPremium) {
      return AppRoutes.paywall;
    }

    return null;
  }
}
