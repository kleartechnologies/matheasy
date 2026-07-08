import '../monitoring/logging_service.dart';

/// Thin facade over [LoggingService].
///
/// Existing call sites (`AppLogger.info/.error/...`) keep working while gaining
/// redaction + automatic Crashlytics forwarding. New code should prefer
/// [LoggingService] directly (it also exposes `warning`/`fatal`/`log`).
class AppLogger {
  const AppLogger._();

  static void debug(String message, {String name = 'matheasy'}) =>
      LoggingService.debug(message, name: name);

  static void info(String message, {String name = 'matheasy'}) =>
      LoggingService.info(message, name: name);

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = 'matheasy',
  }) =>
      LoggingService.error(message,
          error: error, stackTrace: stackTrace, name: name);
}
