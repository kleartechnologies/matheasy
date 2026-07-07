import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Minimal structured logger. In later stages this can forward to Crashlytics;
/// for now it routes through `dart:developer` and is silent in release builds.
class AppLogger {
  const AppLogger._();

  static void debug(String message, {String name = 'matheasy'}) {
    if (kReleaseMode) return;
    developer.log(message, name: name, level: 500);
  }

  static void info(String message, {String name = 'matheasy'}) {
    developer.log(message, name: name, level: 800);
  }

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = 'matheasy',
  }) {
    developer.log(
      message,
      name: name,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
