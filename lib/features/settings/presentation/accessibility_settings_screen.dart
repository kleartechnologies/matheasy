import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/settings_controller.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_switch_tile.dart';

/// Accessibility preferences. Larger Text and Reduced Motion take effect
/// immediately (via the root MediaQuery); High Contrast and Voice Feedback are
/// persisted for a later stage.
class AccessibilitySettingsScreen extends ConsumerWidget {
  const AccessibilitySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a =
        ref.watch(settingsControllerProvider.select((s) => s.accessibility));
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          SettingsSection(
            title: 'Display',
            children: [
              SettingsSwitchTile(
                icon: Icons.format_size_rounded,
                title: 'Larger text',
                subtitle: 'Increase text size across the app',
                value: a.largerText,
                onChanged: (v) => controller.setLargerText(value: v),
              ),
              SettingsSwitchTile(
                icon: Icons.contrast_rounded,
                title: 'High contrast',
                subtitle: 'Boost contrast for readability',
                value: a.highContrast,
                onChanged: (v) => controller.setHighContrast(value: v),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsSection(
            title: 'Motion & audio',
            children: [
              SettingsSwitchTile(
                icon: Icons.motion_photos_off_rounded,
                title: 'Reduced motion',
                subtitle: 'Minimise animations and transitions',
                value: a.reducedMotion,
                onChanged: (v) => controller.setReducedMotion(value: v),
              ),
              SettingsSwitchTile(
                icon: Icons.record_voice_over_rounded,
                title: 'Voice feedback',
                subtitle: 'Spoken hints and confirmations',
                value: a.voiceFeedback,
                onChanged: (v) => controller.setVoiceFeedback(value: v),
              ),
            ],
          ),
          const SettingsNote(
            'High contrast and voice feedback are coming soon — your choices '
            'are saved.',
          ),
        ],
      ),
    );
  }
}
