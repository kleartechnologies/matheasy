import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_service.dart' show firebaseReadyProvider;

/// Crash + non-fatal error reporting. The `firebase_crashlytics` SDK is
/// quarantined to [FirebaseCrashReportingService]; the rest of the app depends
/// only on this interface (mirroring Auth / RevenueCat / Firestore).
abstract interface class CrashReportingService {
  /// Records a non-fatal (or [fatal]) error with an optional human [reason].
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
    String? reason,
  });

  /// Records an uncaught Flutter framework error.
  Future<void> recordFlutterError(FlutterErrorDetails details, {bool fatal = false});

  /// Adds a breadcrumb to the next crash report.
  void log(String message);

  /// Associates subsequent reports with a user (or clears it with `null`).
  Future<void> setUserId(String? id);

  /// Attaches a custom key/value to subsequent reports.
  Future<void> setCustomKey(String key, Object value);

  bool get isEnabled;
}

/// No-op reporter used before Firebase is ready, in tests, and on the
/// unconfigured checkout. Keeps every call site safe with zero setup.
class NoopCrashReportingService implements CrashReportingService {
  const NoopCrashReportingService();

  @override
  bool get isEnabled => false;

  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false, String? reason}) async {}

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details,
      {bool fatal = false}) async {}

  @override
  void log(String message) {}

  @override
  Future<void> setUserId(String? id) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}
}

/// Real Crashlytics-backed reporter. Collection is enabled only in release
/// builds, so debug/profile runs never pollute the Crashlytics dashboard while
/// the wiring stays identical.
class FirebaseCrashReportingService implements CrashReportingService {
  FirebaseCrashReportingService(this._crashlytics);

  final FirebaseCrashlytics _crashlytics;

  /// Configures the instance, enabling collection only in release.
  static Future<FirebaseCrashReportingService> initialize() async {
    final instance = FirebaseCrashlytics.instance;
    await instance.setCrashlyticsCollectionEnabled(kReleaseMode);
    return FirebaseCrashReportingService(instance);
  }

  @override
  bool get isEnabled => true;

  @override
  Future<void> recordError(Object error, StackTrace? stack,
          {bool fatal = false, String? reason}) =>
      _crashlytics.recordError(error, stack, fatal: fatal, reason: reason);

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details,
          {bool fatal = false}) =>
      fatal
          ? _crashlytics.recordFlutterFatalError(details)
          : _crashlytics.recordFlutterError(details);

  @override
  void log(String message) => _crashlytics.log(message);

  @override
  Future<void> setUserId(String? id) =>
      _crashlytics.setUserIdentifier(id ?? '');

  @override
  Future<void> setCustomKey(String key, Object value) =>
      _crashlytics.setCustomKey(key, value);
}

/// Process-wide reporter, set once in `bootstrap` before the [ProviderScope]
/// exists. The pre-DI zone error handlers and the static [Log] facade read this;
/// DI code reads [crashReportingServiceProvider] (which returns the same
/// instance).
class CrashReporting {
  CrashReporting._();

  static CrashReportingService instance = const NoopCrashReportingService();
}

/// Provides the active [CrashReportingService]. Defaults to the global instance
/// configured in bootstrap; overridden in tests.
final Provider<CrashReportingService> crashReportingServiceProvider =
    Provider<CrashReportingService>((ref) {
  // Touch firebaseReady so the provider re-resolves if it ever changes; the
  // real instance is installed globally in bootstrap.
  ref.watch(firebaseReadyProvider);
  return CrashReporting.instance;
});
