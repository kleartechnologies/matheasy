import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/context_extensions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../application/settings_controller.dart';
import '../domain/appearance_settings.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

/// Theme selection — System, Light or Dark. Applied instantly and persisted;
/// `MatheasyApp` reads this to drive `MaterialApp.themeMode`.
class AppearanceSettingsScreen extends ConsumerWidget {
  const AppearanceSettingsScreen({super.key});

  static const Map<ThemeMode, String> _descriptions = {
    ThemeMode.system: 'Match your device settings',
    ThemeMode.light: 'Always use the light theme',
    ThemeMode.dark: 'Always use the dark theme',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode =
        ref.watch(settingsControllerProvider.select((s) => s.appearance.themeMode));
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          SettingsSection(
            title: 'Theme',
            children: [
              for (final option in ThemeMode.values)
                SettingsTile(
                  icon: option.icon,
                  title: option.label,
                  subtitle: _descriptions[option],
                  trailing: option == mode
                      ? Icon(
                          Icons.check_circle_rounded,
                          // A state-bearing icon on a light card — needs AA.
                          color: context.isDark
                              ? AppColors.primaryLight
                              : AppColors.primaryDark,
                        )
                      : const SizedBox(width: 24),
                  onTap: () => controller.setThemeMode(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
