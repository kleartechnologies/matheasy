// Meta Ads integration tests — the Facebook App Events mapping (the app
// taxonomy -> Meta events), the analytics fan-out, and the config gate.
//
// These are pure-Dart: no Facebook SDK / platform channel is touched, so they
// verify the load-bearing logic (correct Meta event per source event, NO
// revenue double-firing, one-fire-per-event, error isolation) without a device.

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/config/meta_config.dart';
import 'package:matheasy/core/monitoring/crash_reporting_service.dart';
import 'package:matheasy/features/analytics/application/analytics_service.dart';
import 'package:matheasy/features/analytics/application/composite_analytics_service.dart';
import 'package:matheasy/features/analytics/domain/analytics_event.dart';
import 'package:matheasy/features/analytics/domain/meta_event.dart';

/// Records every call for assertions.
class _RecordingAnalyticsService implements AnalyticsService {
  final List<AnalyticsEvent> events = [];
  final List<String?> userIds = [];

  @override
  Future<void> logEvent(AnalyticsEvent event) async => events.add(event);

  @override
  Future<void> setUserId(String? id) async => userIds.add(id);

  @override
  Future<void> setUserProperty(String name, String? value) async {}
}

/// Throws on every call — used to prove the fan-out isolates a failing backend.
class _ThrowingAnalyticsService implements AnalyticsService {
  @override
  Future<void> logEvent(AnalyticsEvent event) async => throw StateError('boom');

  @override
  Future<void> setUserId(String? id) async => throw StateError('boom');

  @override
  Future<void> setUserProperty(String name, String? value) async =>
      throw StateError('boom');
}

void main() {
  group('MetaConfig', () {
    test('is not configured with the shipped placeholders', () {
      expect(MetaConfig.isConfigured, isFalse);
      expect(MetaConfig.appId.startsWith('REPLACE_'), isTrue);
      expect(MetaConfig.clientToken.startsWith('REPLACE_'), isTrue);
    });
  });

  group('MetaEventMapper', () {
    test('sign-up maps to CompleteRegistration with the provider', () {
      final meta = MetaEventMapper.map(
        AnalyticsEvent.accountCreated(provider: 'google'),
      );
      expect(
        meta,
        const MetaEvent('fb_mobile_complete_registration', {
          'fb_registration_method': 'google',
        }),
      );
    });

    test('onboarding maps to CompleteTutorial', () {
      expect(
        MetaEventMapper.map(AnalyticsEvent.onboardingCompleted()),
        const MetaEvent('fb_mobile_tutorial_completion'),
      );
    });

    test('the firstScan achievement maps to a one-off FirstScan event', () {
      expect(
        MetaEventMapper.map(
          AnalyticsEvent.achievementUnlocked(id: 'firstScan'),
        ),
        const MetaEvent('FirstScan'),
      );
    });

    test('other achievements are not forwarded to Meta', () {
      expect(
        MetaEventMapper.map(AnalyticsEvent.achievementUnlocked(id: 'streak7')),
        isNull,
      );
    });

    test('a solved problem maps to ViewContent keyed by problem type', () {
      expect(
        MetaEventMapper.map(AnalyticsEvent.resultViewed(problemType: 'linear')),
        const MetaEvent('fb_mobile_content_view', {
          'fb_content_type': 'linear',
        }),
      );
    });

    test('engagement events map to their custom Meta events', () {
      expect(
        MetaEventMapper.map(
          AnalyticsEvent.visualViewed(category: 'algebra', tier: 'animated'),
        ),
        const MetaEvent('VisualLearningOpened'),
      );
      expect(
        MetaEventMapper.map(AnalyticsEvent.tutorOpened()),
        const MetaEvent('AITutorOpened'),
      );
      expect(
        MetaEventMapper.map(AnalyticsEvent.practiceStarted(topic: 'algebra')),
        const MetaEvent('PracticeStarted'),
      );
      expect(
        MetaEventMapper.map(
          AnalyticsEvent.practiceCompleted(correct: 4, total: 5),
        ),
        const MetaEvent('PracticeCompleted', {'correct': 4, 'total': 5}),
      );
    });

    test(
      'paywall view maps to a custom PaywallViewed (impression, not intent)',
      () {
        // Deliberately NOT the standard InitiateCheckout — the paywall auto-opens
        // on limits, so an impression must not inflate that funnel event.
        expect(
          MetaEventMapper.map(
            AnalyticsEvent.paywallViewed(trigger: 'scanLimit'),
          ),
          const MetaEvent('PaywallViewed'),
        );
      },
    );

    test('equal MetaEvents share a hash code (hashCode/== contract)', () {
      const a = MetaEvent('fb_mobile_content_view', {
        'fb_content_type': 'linear',
      });
      const b = MetaEvent('fb_mobile_content_view', {
        'fb_content_type': 'linear',
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test(
      'restore is forwarded, but a purchase is NOT (RevenueCat owns revenue)',
      () {
        expect(
          MetaEventMapper.map(AnalyticsEvent.subscriptionRestored()),
          const MetaEvent('SubscriptionRestored'),
        );
        // The critical no-double-count assertion: revenue is delivered to Meta
        // server-side by RevenueCat's Conversions API, so the client must NOT log
        // a purchase event too.
        expect(
          MetaEventMapper.map(
            AnalyticsEvent.subscriptionPurchased(plan: 'proAnnual'),
          ),
          isNull,
        );
      },
    );

    test('internal/product events are not forwarded to the ad account', () {
      for (final event in [
        AnalyticsEvent.appOpened(),
        AnalyticsEvent.scanStarted(source: 'camera'),
        AnalyticsEvent.scanCompleted(),
        AnalyticsEvent.recognitionSucceeded(source: 'camera', confidence: 90),
        AnalyticsEvent.syncCompleted(downloaded: 1, uploaded: 0),
        AnalyticsEvent.profileEdited(),
      ]) {
        expect(MetaEventMapper.map(event), isNull, reason: event.name);
      }
    });
  });

  group('CompositeAnalyticsService', () {
    setUp(() => CrashReporting.instance = const NoopCrashReportingService());
    tearDown(() => CrashReporting.instance = const NoopCrashReportingService());

    test('fans every call out to all delegates', () async {
      final a = _RecordingAnalyticsService();
      final b = _RecordingAnalyticsService();
      final composite = CompositeAnalyticsService([a, b]);

      await composite.logEvent(AnalyticsEvent.tutorOpened());
      await composite.setUserId('uid-1');

      expect(a.events.single.name, 'tutor_opened');
      expect(b.events.single.name, 'tutor_opened');
      expect(a.userIds.single, 'uid-1');
      expect(b.userIds.single, 'uid-1');
    });

    test(
      'isolates a throwing delegate so the others still receive the call',
      () async {
        final healthy = _RecordingAnalyticsService();
        final composite = CompositeAnalyticsService([
          _ThrowingAnalyticsService(),
          healthy,
        ]);

        // Must not throw despite the first delegate blowing up on every call.
        await composite.logEvent(AnalyticsEvent.scanCompleted());

        expect(healthy.events.single.name, 'scan_completed');
      },
    );
  });
}
