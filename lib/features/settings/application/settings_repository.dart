import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../../practice/domain/practice_difficulty.dart';
import '../domain/accessibility_settings.dart';
import '../domain/appearance_settings.dart';
import '../domain/learning_goal.dart';
import '../domain/learning_preferences.dart';
import '../domain/notification_settings.dart';
import '../domain/profile_settings.dart';

/// The persistence seam for [ProfileSettings]. The controller and UI depend only
/// on this interface, so the backing store can be swapped (a test fake, a future
/// cloud sync) without touching them.
abstract interface class SettingsRepository {
  /// Loads persisted settings, or [ProfileSettings.defaults] when none exist.
  ProfileSettings load();

  /// Persists the full settings payload.
  Future<void> save(ProfileSettings settings);
}

/// Provides the active [SettingsRepository], backed by the local key-value store.
final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (ref) => LocalSettingsRepository(ref.watch(preferencesStoreProvider)),
);

/// A [SettingsRepository] that serializes the whole settings tree to a single
/// JSON blob in [PreferencesStore]. Corrupt or partial payloads degrade to
/// sensible defaults rather than throwing.
class LocalSettingsRepository implements SettingsRepository {
  const LocalSettingsRepository(this._prefs);

  final PreferencesStore _prefs;

  @override
  ProfileSettings load() {
    final raw = _prefs.settingsJson;
    if (raw == null || raw.isEmpty) return ProfileSettings.defaults;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ProfileSettings(
        learning: _learningFromJson(map['learning']),
        notifications: _notificationsFromJson(map['notifications']),
        appearance: _appearanceFromJson(map['appearance']),
        accessibility: _accessibilityFromJson(map['accessibility']),
      );
    } catch (_) {
      return ProfileSettings.defaults;
    }
  }

  @override
  Future<void> save(ProfileSettings settings) {
    final json = <String, dynamic>{
      'learning': _learningToJson(settings.learning),
      'notifications': _notificationsToJson(settings.notifications),
      'appearance': _appearanceToJson(settings.appearance),
      'accessibility': _accessibilityToJson(settings.accessibility),
    };
    return _prefs.setSettingsJson(jsonEncode(json));
  }

  // ---- Serialization ----

  Map<String, dynamic> _learningToJson(LearningPreferences p) => {
        'gradeLevel': p.gradeLevel?.name,
        'learningGoal': p.learningGoal?.name,
        'dailyGoal': p.dailyGoal?.name,
        'topics': [for (final topic in p.topics) topic.name],
        'difficulty': p.difficulty.name,
      };

  LearningPreferences _learningFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return LearningPreferences.defaults;
    return LearningPreferences(
      gradeLevel: _byName(StudyLevel.values, value['gradeLevel']),
      learningGoal: _byName(LearningGoal.values, value['learningGoal']),
      dailyGoal: _byName(DailyGoal.values, value['dailyGoal']),
      topics: {
        for (final name in (value['topics'] as List? ?? const []))
          ?_byName(MathTopic.values, name),
      },
      difficulty: _byName(PracticeDifficulty.values, value['difficulty']) ??
          PracticeDifficulty.medium,
    );
  }

  Map<String, dynamic> _notificationsToJson(NotificationSettings n) => {
        'practiceReminder': n.practiceReminder,
        'dailyGoalReminder': n.dailyGoalReminder,
        'streakReminder': n.streakReminder,
        'achievementReminder': n.achievementReminder,
      };

  NotificationSettings _notificationsFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return NotificationSettings.defaults;
    return NotificationSettings(
      practiceReminder: _bool(value['practiceReminder'], fallback: true),
      dailyGoalReminder: _bool(value['dailyGoalReminder'], fallback: true),
      streakReminder: _bool(value['streakReminder'], fallback: true),
      achievementReminder: _bool(value['achievementReminder'], fallback: true),
    );
  }

  Map<String, dynamic> _appearanceToJson(AppearanceSettings a) => {
        'themeMode': a.themeMode.name,
      };

  AppearanceSettings _appearanceFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return AppearanceSettings.defaults;
    return AppearanceSettings(
      themeMode: _byName(ThemeMode.values, value['themeMode']) ??
          ThemeMode.system,
    );
  }

  Map<String, dynamic> _accessibilityToJson(AccessibilitySettings a) => {
        'largerText': a.largerText,
        'reducedMotion': a.reducedMotion,
        'highContrast': a.highContrast,
        'voiceFeedback': a.voiceFeedback,
      };

  AccessibilitySettings _accessibilityFromJson(Object? value) {
    if (value is! Map<String, dynamic>) return AccessibilitySettings.defaults;
    return AccessibilitySettings(
      largerText: _bool(value['largerText'], fallback: false),
      reducedMotion: _bool(value['reducedMotion'], fallback: false),
      highContrast: _bool(value['highContrast'], fallback: false),
      voiceFeedback: _bool(value['voiceFeedback'], fallback: false),
    );
  }

  bool _bool(Object? value, {required bool fallback}) =>
      value is bool ? value : fallback;

  /// Resolves an enum value by its `.name`, or `null` when absent/unknown.
  T? _byName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
