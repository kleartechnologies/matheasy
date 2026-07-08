import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_service.dart' show firebaseReadyProvider;
import '../domain/analytics_event.dart';

/// Product analytics. The `firebase_analytics` SDK is quarantined to
/// [FirebaseAnalyticsService]; the rest of the app depends only on this
/// interface and [AnalyticsEvent].
abstract interface class AnalyticsService {
  Future<void> logEvent(AnalyticsEvent event);

  /// Associates events with a user id (or clears with `null`).
  Future<void> setUserId(String? id);

  /// Sets a coarse, non-PII user property (e.g. subscription tier).
  Future<void> setUserProperty(String name, String? value);
}

/// No-op analytics used before Firebase is ready, on the unconfigured checkout
/// and in tests.
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> logEvent(AnalyticsEvent event) async {}

  @override
  Future<void> setUserId(String? id) async {}

  @override
  Future<void> setUserProperty(String name, String? value) async {}
}

/// Real Firebase Analytics. Collection is enabled only in release builds so
/// debug/profile runs never pollute production metrics.
class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;

  static Future<FirebaseAnalyticsService> initialize() async {
    final instance = FirebaseAnalytics.instance;
    await instance.setAnalyticsCollectionEnabled(kReleaseMode);
    return FirebaseAnalyticsService(instance);
  }

  @override
  Future<void> logEvent(AnalyticsEvent event) => _analytics.logEvent(
        name: event.name,
        parameters: event.parameters.isEmpty ? null : event.parameters,
      );

  @override
  Future<void> setUserId(String? id) => _analytics.setUserId(id: id);

  @override
  Future<void> setUserProperty(String name, String? value) =>
      _analytics.setUserProperty(name: name, value: value);
}

/// Process-wide analytics instance, installed in `bootstrap` (the real Firebase
/// service when configured, else the no-op). DI reads
/// [analyticsServiceProvider].
class Analytics {
  Analytics._();

  static AnalyticsService instance = const NoopAnalyticsService();
}

/// Provides the active [AnalyticsService] — the instance installed in bootstrap.
final Provider<AnalyticsService> analyticsServiceProvider =
    Provider<AnalyticsService>((ref) {
  ref.watch(firebaseReadyProvider);
  return Analytics.instance;
});
