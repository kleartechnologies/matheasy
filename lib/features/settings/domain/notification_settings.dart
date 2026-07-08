import 'package:flutter/foundation.dart';

/// Local notification preferences.
///
/// STAGE 10: preference infrastructure only — the app persists these choices but
/// does NOT schedule push notifications yet. Every reminder defaults to on so a
/// later stage that wires up notifications is opt-out, not opt-in.
@immutable
class NotificationSettings {
  const NotificationSettings({
    this.practiceReminder = true,
    this.dailyGoalReminder = true,
    this.streakReminder = true,
    this.achievementReminder = true,
  });

  static const NotificationSettings defaults = NotificationSettings();

  final bool practiceReminder;
  final bool dailyGoalReminder;
  final bool streakReminder;
  final bool achievementReminder;

  NotificationSettings copyWith({
    bool? practiceReminder,
    bool? dailyGoalReminder,
    bool? streakReminder,
    bool? achievementReminder,
  }) {
    return NotificationSettings(
      practiceReminder: practiceReminder ?? this.practiceReminder,
      dailyGoalReminder: dailyGoalReminder ?? this.dailyGoalReminder,
      streakReminder: streakReminder ?? this.streakReminder,
      achievementReminder: achievementReminder ?? this.achievementReminder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NotificationSettings &&
      other.practiceReminder == practiceReminder &&
      other.dailyGoalReminder == dailyGoalReminder &&
      other.streakReminder == streakReminder &&
      other.achievementReminder == achievementReminder;

  @override
  int get hashCode => Object.hash(
        practiceReminder,
        dailyGoalReminder,
        streakReminder,
        achievementReminder,
      );
}
