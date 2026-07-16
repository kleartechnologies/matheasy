import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/animations/floaty.dart';
import '../../../core/brand/brand.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/extensions/context_extensions.dart';
import '../../../core/router/app_routes.dart';
import '../../../core/session/app_session.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/application/auth_controller.dart';

/// The launch screen — a premium first impression built around the official
/// Matheasy logo. After a minimum display window it hands off to the router,
/// which (via the navigation guards) routes to onboarding, auth or home.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  /// Minimum time the splash is shown before routing onward.
  static const Duration minDisplay = Duration(milliseconds: 1600);

  /// Hard cap on how long we wait for the auth session to resolve before
  /// handing off anyway, so a stalled auth backend can never trap the user here.
  static const Duration maxWait = Duration(seconds: 5);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _minTimer;
  Timer? _maxTimer;
  bool _minElapsed = false;
  bool _routed = false;

  @override
  void initState() {
    super.initState();
    _minTimer = Timer(SplashScreen.minDisplay, () {
      _minElapsed = true;
      _maybeRouteOnward();
    });
    // Safety net: never wait longer than [maxWait] for auth to settle.
    _maxTimer = Timer(SplashScreen.maxWait, _forceRouteOnward);
  }

  @override
  void dispose() {
    _minTimer?.cancel();
    _maxTimer?.cancel();
    super.dispose();
  }

  /// Routes on once the minimum splash time has elapsed AND the auth session
  /// has resolved (so we never flash onboarding/auth before the guard knows
  /// whether a session was restored).
  void _maybeRouteOnward() {
    if (_routed || !mounted || !_minElapsed) return;
    if (ref.read(authStatusProvider) == AuthStatus.unknown) return;
    _go();
  }

  void _forceRouteOnward() {
    if (_routed || !mounted) return;
    _go();
  }

  void _go() {
    _routed = true;
    // Hand off to the guard, which is the single source of truth for where a
    // launching user should land.
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    // Re-check the hand-off whenever the auth session resolves.
    ref.listen(authStatusProvider, (_, _) => _maybeRouteOnward());
    final colors = context.colors;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The official vertical logo lockup (mark above wordmark) is the
            // hero identity, and it stands on its own: the emerald radial glow
            // that used to sit behind it is gone. The brand does not glow — and
            // the launch screen this dissolves out of is a flat brand colour, so
            // a halo appearing only once Flutter boots read as a seam.
            AppTransitions.scaleIn(
              child: const Floaty(
                child: MatheasyLogo(
                  variant: MatheasyLogoVariant.vertical,
                  markSize: 84,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppTransitions.fadeIn(
              child: Text(
                AppConstants.appTagline,
                style: AppTypography.bodyLarge
                    .copyWith(color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
