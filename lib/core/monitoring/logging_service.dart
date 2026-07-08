import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'crash_reporting_service.dart';
import 'log_level.dart';

/// Centralized, level-aware logging with sensitive-data redaction and automatic
/// crash-reporting forwarding.
///
/// Static (like the [AppLogger] it replaces) so it works everywhere, including
/// the pre-`ProviderScope` bootstrap zone. Behaviour:
/// * everything routes to `dart:developer` ([LogLevel.debug] is dropped in
///   release);
/// * [LogLevel.warning] and above are forwarded to [CrashReporting.instance]
///   (warnings as breadcrumbs, errors/fatals as (non-)fatal records);
/// * every log **message** and crash **reason** is [redact]ed first, so emails,
///   tokens and keys in those strings never reach logs or Crashlytics. Note the
///   raw `error` object is forwarded verbatim (its type/stack drive Crashlytics
///   grouping), so exception *messages* must not embed PII — pass the sensitive
///   detail in the log message (which is redacted) instead.
class LoggingService {
  const LoggingService._();

  static const String _defaultName = 'matheasy';

  static void debug(String message, {String name = _defaultName}) =>
      log(LogLevel.debug, message, name: name);

  static void info(String message, {String name = _defaultName}) =>
      log(LogLevel.info, message, name: name);

  static void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = _defaultName,
  }) =>
      log(LogLevel.warning, message,
          error: error, stackTrace: stackTrace, name: name);

  static void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = _defaultName,
  }) =>
      log(LogLevel.error, message,
          error: error, stackTrace: stackTrace, name: name);

  static void fatal(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = _defaultName,
  }) =>
      log(LogLevel.fatal, message,
          error: error, stackTrace: stackTrace, name: name);

  static void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String name = _defaultName,
  }) {
    if (level == LogLevel.debug && kReleaseMode) return;
    final safeMessage = redact(message);

    developer.log(
      safeMessage,
      name: name,
      level: level.value,
      error: error,
      stackTrace: stackTrace,
    );

    if (!level.reportsToCrashlytics) return;
    final crash = CrashReporting.instance;
    if (level >= LogLevel.error) {
      // Attach the message as the crash reason; redaction keeps it PII-free.
      crash.recordError(
        error ?? safeMessage,
        stackTrace,
        fatal: level == LogLevel.fatal,
        reason: safeMessage,
      );
    } else {
      crash.log('[${level.label}] $safeMessage');
    }
  }

  // ---- Redaction ----

  static final RegExp _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final RegExp _bearer =
      RegExp(r'bearer\s+[A-Za-z0-9._-]+', caseSensitive: false);
  static final RegExp _apiKey = RegExp(
    r'(sk|pk|rk|appl|goog)[_-][A-Za-z0-9_-]{12,}',
    caseSensitive: false,
  );
  static final RegExp _longToken = RegExp(r'\b[A-Za-z0-9_-]{32,}\b');

  /// Masks anything that looks like PII or a credential. Conservative by design
  /// — over-redacting a log line is always safer than leaking a secret.
  static String redact(String input) {
    return input
        .replaceAll(_email, '[redacted-email]')
        .replaceAll(_bearer, 'Bearer [redacted-token]')
        .replaceAll(_apiKey, '[redacted-key]')
        .replaceAll(_longToken, '[redacted]');
  }
}
