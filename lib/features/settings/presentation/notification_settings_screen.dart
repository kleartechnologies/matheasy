import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_spacing.dart';
import '../application/settings_controller.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_switch_tile.dart';

/// Reminder preferences. Persists the learner's choices; actual scheduling of
/// notifications is deferred to a later stage (this is infrastructure + UI).
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(settingsControllerProvider.select((s) => s.notifications));
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          SettingsSection(
            title: 'Reminders',
            children: [
              SettingsSwitchTile(
                icon: Icons.fitness_center_rounded,
                title: 'Practice reminder',
                subtitle: 'Nudge me to keep practising',
                value: n.practiceReminder,
                onChanged: (v) => controller.setPracticeReminder(value: v),
              ),
              SettingsSwitchTile(
                icon: Icons.flag_rounded,
                title: 'Daily goal reminder',
                subtitle: 'Remind me to hit my daily goal',
                value: n.dailyGoalReminder,
                onChanged: (v) => controller.setDailyGoalReminder(value: v),
              ),
              SettingsSwitchTile(
                icon: Icons.local_fire_department_rounded,
                title: 'Streak reminder',
                subtitle: "Don't let my streak slip",
                value: n.streakReminder,
                onChanged: (v) => controller.setStreakReminder(value: v),
              ),
              SettingsSwitchTile(
                icon: Icons.emoji_events_rounded,
                title: 'Achievement reminder',
                subtitle: 'Celebrate new badges',
                value: n.achievementReminder,
                onChanged: (v) => controller.setAchievementReminder(value: v),
              ),
            ],
          ),
          const SettingsNote(
            "Notifications aren't sent yet — your choices are saved for when "
            'reminders arrive.',
          ),
        ],
      ),
    );
  }
}
