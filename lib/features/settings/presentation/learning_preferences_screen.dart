import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_language.dart';
import '../../../core/localization/l10n_extension.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/widgets.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../application/settings_controller.dart';
import '../domain/learning_goal.dart';
import 'widgets/practice_difficulty_selector.dart';
import 'widgets/settings_option_picker.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

/// Edits the learner's study preferences: grade level, learning goal, daily
/// goal, practice difficulty and focus topics — all persisted immediately.
class LearningPreferencesScreen extends ConsumerWidget {
  const LearningPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final learning =
        ref.watch(settingsControllerProvider.select((s) => s.learning));
    final controller = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settingsLearningPreferences)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          AppSpacing.lg,
          AppSpacing.screenH,
          AppSpacing.xxxl,
        ),
        children: [
          SettingsSection(
            title: context.l10n.settingsStudyProfile,
            children: [
              SettingsTile(
                icon: Icons.language_rounded,
                title: context.l10n.settingsLanguage,
                value: learning.language.nativeName,
                onTap: () => showSettingsOptionPicker<AppLanguage>(
                  context,
                  title: context.l10n.settingsLanguage,
                  options: AppLanguage.values,
                  selected: learning.language,
                  label: (o) => o.nativeName,
                  subtitle: (o) => o.englishName,
                  icon: (o) => Icons.translate_rounded,
                  onSelected: controller.setLanguage,
                ),
              ),
              SettingsTile(
                icon: Icons.school_rounded,
                title: context.l10n.settingsGradeLevel,
                value: learning.gradeLevel?.label ?? context.l10n.commonNotSet,
                onTap: () => showSettingsOptionPicker<StudyLevel>(
                  context,
                  title: context.l10n.settingsGradeLevel,
                  options: StudyLevel.values,
                  selected: learning.gradeLevel,
                  label: (o) => o.label,
                  icon: (o) => o.icon,
                  onSelected: controller.setGradeLevel,
                ),
              ),
              SettingsTile(
                icon: Icons.emoji_objects_rounded,
                title: context.l10n.settingsLearningGoal,
                value: learning.learningGoal?.label ?? context.l10n.commonNotSet,
                onTap: () => showSettingsOptionPicker<LearningGoal>(
                  context,
                  title: context.l10n.settingsLearningGoal,
                  options: LearningGoal.values,
                  selected: learning.learningGoal,
                  label: (o) => o.label,
                  icon: (o) => o.icon,
                  onSelected: controller.setLearningGoal,
                ),
              ),
              SettingsTile(
                icon: Icons.timer_rounded,
                title: context.l10n.settingsDailyGoal,
                value: learning.dailyGoal?.label ?? context.l10n.commonNotSet,
                onTap: () => showSettingsOptionPicker<DailyGoal>(
                  context,
                  title: context.l10n.settingsDailyGoal,
                  options: DailyGoal.values,
                  selected: learning.dailyGoal,
                  label: (o) => o.label,
                  icon: (o) => Icons.bolt_rounded,
                  trailing: (o) => o.tag,
                  onSelected: controller.setDailyGoal,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsGroupLabel(context.l10n.settingsPracticeDifficulty),
          PracticeDifficultySelector(
            selected: learning.difficulty,
            onChanged: controller.setDifficulty,
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsGroupLabel(context.l10n.settingsFocusTopics),
          _TopicPicker(
            selected: learning.topics,
            onToggle: controller.toggleTopic,
          ),
        ],
      ),
    );
  }
}

class _TopicPicker extends StatelessWidget {
  const _TopicPicker({required this.selected, required this.onToggle});

  final Set<MathTopic> selected;
  final ValueChanged<MathTopic> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final topic in MathTopic.values)
          FeatureChip(
            label: topic.label,
            icon: topic.icon,
            selected: selected.contains(topic),
            onTap: () => onToggle(topic),
          ),
      ],
    );
  }
}
