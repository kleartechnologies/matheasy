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
      builder: (context, child) => _AccessibilityScope(
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
class _AccessibilityScope extends StatelessWidget {
  const _AccessibilityScope({
    required this.accessibility,
    required this.child,
  });

  final AccessibilitySettings accessibility;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    var data = media;
    if (accessibility.largerText) {
      data = data.copyWith(
        textScaler: TextScaler.linear(accessibility.textScale),
      );
    }
    if (accessibility.reducedMotion) {
      data = data.copyWith(disableAnimations: true);
    }
    if (data == media) return child;
    return MediaQuery(data: data, child: child);
  }
}
