// Stage 13 tests — Production Hardening observability + security.
//
// Covers the analytics event taxonomy, the logging service (redaction + crash
// forwarding + levels), the client rate limiter (sliding window), the
// diagnostics builder, and the server-validation seam.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/monitoring/crash_reporting_service.dart';
import 'package:matheasy/core/monitoring/log_level.dart';
import 'package:matheasy/core/monitoring/logging_service.dart';
import 'package:matheasy/core/security/rate_limit_result.dart';
import 'package:matheasy/core/security/rate_limit_service.dart';
import 'package:matheasy/core/security/server_validation_service.dart';
import 'package:matheasy/core/session/app_session.dart';
import 'package:matheasy/features/analytics/domain/analytics_event.dart';
import 'package:matheasy/features/diagnostics/application/diagnostics_service.dart';
import 'package:matheasy/features/diagnostics/domain/diagnostic_status.dart';
import 'package:matheasy/features/sync/domain/sync_status.dart';

/// Captures forwarded reports so we can assert on them.
class _FakeCrashReporter implements CrashReportingService {
  final List<String> reasons = [];
  final List<String> logs = [];
  Object? lastError;
  bool lastFatal = false;

  @override
  bool get isEnabled => true;

  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {bool fatal = false, String? reason}) async {
    lastError = error;
    lastFatal = fatal;
    if (reason != null) reasons.add(reason);
  }

  @override
  Future<void> recordFlutterError(FlutterErrorDetails details,
      {bool fatal = false}) async {}

  @override
  void log(String message) => logs.add(message);

  @override
  Future<void> setUserId(String? id) async {}

  @override
  Future<void> setCustomKey(String key, Object value) async {}
}

void main() {
  group('AnalyticsEvent taxonomy', () {
    test('names are snake_case and within GA4 limits', () {
      final events = [
        AnalyticsEvent.appOpened(),
        AnalyticsEvent.onboardingCompleted(),
        AnalyticsEvent.accountCreated(provider: 'google'),
        AnalyticsEvent.scanStarted(source: 'camera'),
        AnalyticsEvent.scanCompleted(),
        AnalyticsEvent.resultViewed(problemType: 'linear'),
        AnalyticsEvent.visualViewed(
            category: 'algebra', tier: 'animatedTransformation'),
        AnalyticsEvent.visualTeaserViewed(),
        AnalyticsEvent.tutorOpened(),
        AnalyticsEvent.tutorMessageSent(),
        AnalyticsEvent.practiceStarted(topic: 'algebra'),
        AnalyticsEvent.practiceCompleted(correct: 4, total: 5),
        AnalyticsEvent.achievementUnlocked(id: 'firstScan'),
        AnalyticsEvent.paywallViewed(trigger: 'scanLimit'),
        AnalyticsEvent.subscriptionPurchased(plan: 'proAnnual'),
        AnalyticsEvent.subscriptionRestored(),
        AnalyticsEvent.profileEdited(),
        AnalyticsEvent.syncCompleted(downloaded: 2, uploaded: 1),
      ];
      expect(events.length, 18);
      final snake = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
      for (final e in events) {
        expect(snake.hasMatch(e.name), isTrue, reason: e.name);
        for (final value in e.parameters.values) {
          expect(value, anyOf(isA<String>(), isA<num>()));
        }
      }
    });

    test('carries the expected parameters', () {
      expect(AnalyticsEvent.practiceCompleted(correct: 4, total: 5).parameters,
          {'correct': 4, 'total': 5});
      expect(AnalyticsEvent.scanStarted(source: 'gallery').parameters,
          {'source': 'gallery'});
    });
  });

  group('LoggingService', () {
    setUp(() => CrashReporting.instance = const NoopCrashReportingService());
    tearDown(() => CrashReporting.instance = const NoopCrashReportingService());

    test('redacts emails, tokens and keys', () {
      expect(LoggingService.redact('user ada@matheasy.app signed in'),
          contains('[redacted-email]'));
      expect(LoggingService.redact('Authorization: Bearer abc.def-123'),
          contains('[redacted-token]'));
      expect(LoggingService.redact('key sk_live_abcdef1234567890'),
          isNot(contains('sk_live_abcdef1234567890')));
    });

    test('forwards errors (with redacted reason) to crash reporting', () {
      final fake = _FakeCrashReporter();
      CrashReporting.instance = fake;

      LoggingService.error('Failed for ada@matheasy.app', error: StateError('x'));

      expect(fake.lastFatal, isFalse);
      expect(fake.reasons.single, contains('[redacted-email]'));
      expect(fake.reasons.single, isNot(contains('ada@matheasy.app')));
    });

    test('fatal is reported as fatal; info/debug are not forwarded', () {
      final fake = _FakeCrashReporter();
      CrashReporting.instance = fake;

      LoggingService.info('just info');
      LoggingService.fatal('boom', error: StateError('y'));

      expect(fake.lastFatal, isTrue);
      expect(fake.reasons, hasLength(1)); // info not forwarded
    });

    test('warnings are logged as breadcrumbs, not error records', () {
      final fake = _FakeCrashReporter();
      CrashReporting.instance = fake;

      LoggingService.warning('careful');
      expect(fake.logs.single, contains('WARNING'));
      expect(fake.reasons, isEmpty);
    });

    test('log levels order and forwarding flags', () {
      expect(LogLevel.error >= LogLevel.warning, isTrue);
      expect(LogLevel.debug.reportsToCrashlytics, isFalse);
      expect(LogLevel.warning.reportsToCrashlytics, isTrue);
    });
  });

  group('RateLimitService', () {
    test('allows up to the limit then blocks, and recovers after the window',
        () {
      var now = DateTime(2026, 7, 8, 12);
      final service = RateLimitService(() => now);

      // Scan limit is 20/min.
      for (var i = 0; i < 20; i++) {
        expect(service.check(RateLimitedAction.scan).allowed, isTrue);
      }
      final blocked = service.check(RateLimitedAction.scan);
      expect(blocked.isLimited, isTrue);
      expect(blocked.retryAfter, isNotNull);

      // Advance past the window → allowed again.
      now = now.add(const Duration(minutes: 1, seconds: 1));
      expect(service.check(RateLimitedAction.scan).allowed, isTrue);
    });

    test('actions are limited independently', () {
      final now = DateTime(2026, 7, 8, 12);
      final service = RateLimitService(() => now);
      for (var i = 0; i < 20; i++) {
        service.check(RateLimitedAction.scan);
      }
      expect(service.check(RateLimitedAction.scan).isLimited, isTrue);
      // Tutor is untouched.
      expect(service.check(RateLimitedAction.tutorMessage).allowed, isTrue);
    });
  });

  group('DiagnosticsService', () {
    test('maps subsystem state to statuses + build info', () {
      final report = DiagnosticsService.build(
        firebaseReady: true,
        revenueCatReady: false,
        isPro: false,
        syncStatus: SyncStatus.offline,
        authStatus: AuthStatus.authenticated,
        isGuest: true,
        crashlyticsEnabled: false,
      );

      DiagnosticStatus statusOf(String label) =>
          report.subsystems.firstWhere((e) => e.label == label).status;

      expect(statusOf('Firebase'), DiagnosticStatus.ok);
      expect(statusOf('RevenueCat'), DiagnosticStatus.disabled);
      expect(statusOf('Cloud sync'), DiagnosticStatus.degraded);
      expect(statusOf('Auth'), DiagnosticStatus.ok);
      expect(statusOf('Crashlytics'), DiagnosticStatus.disabled);
      expect(report.appVersion, isNotEmpty);
      // Offline sync makes the overall degraded (disabled rows are ignored).
      expect(report.overall, DiagnosticStatus.degraded);
    });
  });

  group('ServerValidationService (seam)', () {
    test('local-trust allows but is not server-verified', () async {
      const service = LocalTrustServerValidationService();
      final entitlement = await service.validateEntitlement();
      final usage = await service.validateUsage('scan');
      expect(entitlement.allowed, isTrue);
      expect(entitlement.serverVerified, isFalse);
      expect(usage.serverVerified, isFalse);
    });
  });
}
