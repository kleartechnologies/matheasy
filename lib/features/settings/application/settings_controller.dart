import 'dart:async';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/localization/app_language.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../../practice/domain/practice_difficulty.dart';
import '../domain/learning_goal.dart';
import '../domain/profile_settings.dart';
import 'settings_repository.dart';

part 'settings_controller.g.dart';

/// The single source of truth for every locally-persisted setting.
///
/// Hydrates synchronously from [SettingsRepository] on launch (SharedPreferences
/// is preloaded in bootstrap) and persists every change fire-and-forget, so the
/// UI updates instantly. `MatheasyApp` reads [ProfileSettings.appearance] and
/// [ProfileSettings.accessibility] from here to drive the theme and root
/// MediaQuery.
@Riverpod(keepAlive: true)
class SettingsController extends _$SettingsController {
  @override
  ProfileSettings build() => ref.read(settingsRepositoryProvider).load();

  void _update(ProfileSettings next) {
    state = next;
    unawaited(ref.read(settingsRepositoryProvider).save(next));
  }

  // ---- Learning preferences ----

  void setGradeLevel(StudyLevel level) => _update(
        state.copyWith(learning: state.learning.copyWith(gradeLevel: level)),
      );

  void setLearningGoal(LearningGoal goal) => _update(
        state.copyWith(learning: state.learning.copyWith(learningGoal: goal)),
      );

  void setDailyGoal(DailyGoal goal) => _update(
        state.copyWith(learning: state.learning.copyWith(dailyGoal: goal)),
      );

  void toggleTopic(MathTopic topic) {
    final next = {...state.learning.topics};
    if (!next.add(topic)) next.remove(topic);
    _update(state.copyWith(learning: state.learning.copyWith(topics: next)));
  }

  void setDifficulty(PracticeDifficulty difficulty) => _update(
        state.copyWith(
          learning: state.learning.copyWith(difficulty: difficulty),
        ),
      );

  /// Changes the learning language. Takes effect immediately (no restart): the
  /// UI locale re-renders and every subsequent AI request carries the new
  /// language, so future explanations, practice, tutor replies and hints follow.
  void setLanguage(AppLanguage language) => _update(
        state.copyWith(
          learning: state.learning.copyWith(language: language),
        ),
      );

  // ---- Notification reminders ----

  void setPracticeReminder({required bool value}) => _update(
        state.copyWith(
          notifications:
              state.notifications.copyWith(practiceReminder: value),
        ),
      );

  void setDailyGoalReminder({required bool value}) => _update(
        state.copyWith(
          notifications:
              state.notifications.copyWith(dailyGoalReminder: value),
        ),
      );

  void setStreakReminder({required bool value}) => _update(
        state.copyWith(
          notifications: state.notifications.copyWith(streakReminder: value),
        ),
      );

  void setAchievementReminder({required bool value}) => _update(
        state.copyWith(
          notifications:
              state.notifications.copyWith(achievementReminder: value),
        ),
      );

  // ---- Appearance / theme ----

  void setThemeMode(ThemeMode mode) => _update(
        state.copyWith(appearance: state.appearance.copyWith(themeMode: mode)),
      );

  /// Flips between explicit light and dark (used by the gallery toggle).
  void toggleTheme(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark);
  }

  // ---- Accessibility ----

  void setLargerText({required bool value}) => _update(
        state.copyWith(
          accessibility: state.accessibility.copyWith(largerText: value),
        ),
      );

  void setReducedMotion({required bool value}) => _update(
        state.copyWith(
          accessibility: state.accessibility.copyWith(reducedMotion: value),
        ),
      );

  void setHighContrast({required bool value}) => _update(
        state.copyWith(
          accessibility: state.accessibility.copyWith(highContrast: value),
        ),
      );

  void setVoiceFeedback({required bool value}) => _update(
        state.copyWith(
          accessibility: state.accessibility.copyWith(voiceFeedback: value),
        ),
      );

  // ---- Lifecycle ----

  /// Restores every setting to its default (used by "Delete Account").
  void reset() => _update(ProfileSettings.defaults);
}
