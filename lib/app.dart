import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/analytics/application/analytics_controller.dart';
import 'features/progress/presentation/widgets/achievement_celebration_host.dart';
import 'features/settings/application/settings_controller.dart';
import 'features/settings/domain/accessibility_settings.dart';

/// Root application widget. Wires the router (with navigation guards) and the
/// light/dark themes, reacting to the persisted appearance + accessibility
/// preferences from [SettingsController].
class MatheasyApp extends ConsumerWidget {
  const MatheasyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final router = ref.watch(goRouterProvider);
    // Keep the analytics engine alive from the root — before onboarding/auth —
    // so state-derived events (onboarding completed, achievements) are captured.
    ref.watch(analyticsControllerProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.appearance.themeMode,
      routerConfig: router,
      // Apply accessibility overrides, then surface achievement-unlock
      // celebrations above every route.
      builder: (context, child) => AccessibilityScope(
        accessibility: settings.accessibility,
        child: AchievementCelebrationHost(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// Applies the learner's [AccessibilitySettings] to the root [MediaQuery] so the
/// whole app honours them: [AccessibilitySettings.largerText] bumps text scaling
/// and [AccessibilitySettings.reducedMotion] suppresses implicit animations.
///
/// When both are off the OS settings pass through untouched (no override).
///
/// Public (not `_`-prefixed) so [largerTextScaler] can be unit-tested directly.
class AccessibilityScope extends StatelessWidget {
  const AccessibilityScope({
    super.key,
    required this.accessibility,
    required this.child,
  });

  final AccessibilitySettings accessibility;
  final Widget child;

  /// Font size the OS scaler is probed at to recover its effective factor.
  /// A [TextScaler] is not required to be linear, so the factor is measured at
  /// body size rather than assumed.
  static const double _probeFontSize = 16;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    var data = media;
    if (accessibility.largerText) {
      // Compose with the OS scaler, never replace it: the old
      // `TextScaler.linear(1.15)` pinned a learner already at 2.0x system scale
      // *down* to 1.15x, shrinking text for exactly the people the toggle exists
      // for. Instead we lift the effective factor 15% above the OS scale.
      //
      // This must be a plain linear scaler, NOT `media.textScaler.clamp(min:…)`.
      // A min-floored clamp does not COMPOSE with a descendant that caps text
      // (the tab bar clamps its micro-labels to 1.3x): clamping [0, 1.3] onto an
      // inherited [floor, ∞] scaler yields [floor, 1.3], and `_ClampedTextScaler`
      // asserts `max > min` — so any learner at OS scale ≥ ~1.13 would crash the
      // tab bar on every build (or, in release, silently overflow the capped
      // cell). A linear scaler carries no floor, so descendant caps stay valid.
      data = data.copyWith(
        textScaler: largerTextScaler(media.textScaler, accessibility.textScale),
      );
    }
    if (accessibility.reducedMotion) {
      data = data.copyWith(disableAnimations: true);
    }
    if (data == media) return child;
    return MediaQuery(data: data, child: child);
  }

  /// The scaler the "Larger text" toggle applies over an inherited [os] scaler.
  ///
  /// Pulled out and made pure so it can be unit-tested — see
  /// `test/accessibility_text_scale_test.dart`, which pins both invariants:
  /// the result is never below the OS scale, and it composes with a descendant
  /// text cap (the tab bar's 1.3×) without asserting.
  ///
  /// It returns a plain linear scaler on purpose. See the note at the call site:
  /// a min-floored `os.clamp(min:…)` does NOT compose — clamping `[0, 1.3]` onto
  /// an inherited `[floor, ∞]` yields `[floor, 1.3]`, and `_ClampedTextScaler`
  /// asserts `max > min`, crashing any capped descendant when `floor > 1.3`.
  static TextScaler largerTextScaler(TextScaler os, double factor) {
    final osScale = os.scale(_probeFontSize) / _probeFontSize;
    return TextScaler.linear(osScale * factor);
  }
}
