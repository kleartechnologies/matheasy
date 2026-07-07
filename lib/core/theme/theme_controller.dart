import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'theme_controller.g.dart';

/// Controls the app-wide [ThemeMode].
///
/// Stage 0 keeps this in memory only; a later stage will persist the choice
/// (SharedPreferences / Isar) and hydrate it on launch.
@riverpod
class ThemeModeController extends _$ThemeModeController {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;

  /// Cycles system → light → dark → system.
  void cycle() {
    state = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
  }

  /// Flips between explicit light and dark (used by the gallery toggle).
  void toggle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    state = isDark ? ThemeMode.light : ThemeMode.dark;
  }
}
