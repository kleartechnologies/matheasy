import 'package:flutter/foundation.dart';

import 'accessibility_settings.dart';
import 'appearance_settings.dart';
import 'learning_preferences.dart';
import 'notification_settings.dart';

/// The aggregate of every locally-persisted setting — the payload owned by
/// `SettingsController` and serialized as a single JSON blob by
/// `SettingsRepository`.
@immutable
class ProfileSettings {
  const ProfileSettings({
    this.learning = LearningPreferences.defaults,
    this.notifications = NotificationSettings.defaults,
    this.appearance = AppearanceSettings.defaults,
    this.accessibility = AccessibilitySettings.defaults,
  });

  static const ProfileSettings defaults = ProfileSettings();

  final LearningPreferences learning;
  final NotificationSettings notifications;
  final AppearanceSettings appearance;
  final AccessibilitySettings accessibility;

  ProfileSettings copyWith({
    LearningPreferences? learning,
    NotificationSettings? notifications,
    AppearanceSettings? appearance,
    AccessibilitySettings? accessibility,
  }) {
    return ProfileSettings(
      learning: learning ?? this.learning,
      notifications: notifications ?? this.notifications,
      appearance: appearance ?? this.appearance,
      accessibility: accessibility ?? this.accessibility,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileSettings &&
      other.learning == learning &&
      other.notifications == notifications &&
      other.appearance == appearance &&
      other.accessibility == accessibility;

  @override
  int get hashCode =>
      Object.hash(learning, notifications, appearance, accessibility);
}
