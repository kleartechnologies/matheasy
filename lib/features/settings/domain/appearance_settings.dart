import 'package:flutter/material.dart';

/// Appearance preferences — currently the app-wide [ThemeMode] selection.
///
/// This is the single source of truth for the theme; `MatheasyApp` reads it
/// (via `SettingsController`) and feeds it to `MaterialApp.themeMode`.
@immutable
class AppearanceSettings {
  const AppearanceSettings({this.themeMode = ThemeMode.system});

  static const AppearanceSettings defaults = AppearanceSettings();

  final ThemeMode themeMode;

  AppearanceSettings copyWith({ThemeMode? themeMode}) =>
      AppearanceSettings(themeMode: themeMode ?? this.themeMode);

  @override
  bool operator ==(Object other) =>
      other is AppearanceSettings && other.themeMode == themeMode;

  @override
  int get hashCode => themeMode.hashCode;
}

/// Human-facing label + icon for a [ThemeMode], used by the appearance picker.
extension ThemeModeDisplay on ThemeMode {
  String get label => switch (this) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  IconData get icon => switch (this) {
        ThemeMode.system => Icons.brightness_auto_rounded,
        ThemeMode.light => Icons.light_mode_rounded,
        ThemeMode.dark => Icons.dark_mode_rounded,
      };
}
