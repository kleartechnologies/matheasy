import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/animations/app_transitions.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_durations.dart';
import '../../../core/theme/app_spacing.dart';
import '../../sync/presentation/sync_settings_section.dart';
import '../application/settings_controller.dart';
import '../domain/appearance_settings.dart';
import '../domain/learning_preferences.dart';
import 'about_screen.dart';
import 'accessibility_settings_screen.dart';
import 'appearance_settings_screen.dart';
import 'learning_preferences_screen.dart';
import 'legal_document_screen.dart';
import 'notification_settings_screen.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

/// The Settings hub — a categorised list (Apple-Settings style) that drills into
/// learning preferences, app preferences and about/legal pages. Account actions
/// (sign out, delete, upgrade) live on the Profile screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  String _learningSummary(LearningPreferences learning) {
    final parts = <String>[
      if (learning.gradeLevel != null) learning.gradeLevel!.label,
      learning.difficulty.label,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    final sections = <Widget>[
      SettingsSection(
        title: 'Learning',
        children: [
          SettingsTile(
            icon: Icons.tune_rounded,
            title: 'Learning preferences',
            subtitle: _learningSummary(settings.learning),
            onTap: () => _open(context, const LearningPreferencesScreen()),
          ),
        ],
      ),
      SettingsSection(
        title: 'App',
        children: [
          SettingsTile(
            icon: Icons.notifications_none_rounded,
            title: 'Notifications',
            onTap: () => _open(context, const NotificationSettingsScreen()),
          ),
          SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Appearance',
            value: settings.appearance.themeMode.label,
            onTap: () => _open(context, const AppearanceSettingsScreen()),
          ),
          SettingsTile(
            icon: Icons.accessibility_new_rounded,
            title: 'Accessibility',
            onTap: () => _open(context, const AccessibilitySettingsScreen()),
          ),
        ],
      ),
      const SyncSettingsSection(),
      SettingsSection(
        title: 'About',
        children: [
          SettingsTile(
            icon: Icons.shield_outlined,
            title: 'Privacy Policy',
            onTap: () => _open(
              context,
              const LegalDocumentScreen(document: LegalDocument.privacy),
            ),
          ),
          SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            onTap: () => _open(
              context,
              const LegalDocumentScreen(document: LegalDocument.terms),
            ),
          ),
          SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'About Matheasy',
            value: 'v${AppConstants.appVersion}',
            onTap: () => _open(context, const AboutScreen()),
          ),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.section),
        itemBuilder: (context, index) => AppTransitions.slideUp(
          delay: Duration(milliseconds: (index * 60).clamp(0, 240)),
          duration: AppDurations.slow,
          child: sections[index],
        ),
      ),
    );
  }
}
