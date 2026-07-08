import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/progress/presentation/widgets/achievement_celebration_host.dart';

/// Root application widget. Wires the router (with navigation guards) and the
/// light/dark themes, reacting to the [ThemeModeController].
class MatheasyApp extends ConsumerWidget {
  const MatheasyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      // Surface achievement-unlock celebrations above every route.
      builder: (context, child) =>
          AchievementCelebrationHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
