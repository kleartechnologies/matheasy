// Meta Ads integration tests — the Facebook App Events mapping (the app
// taxonomy -> Meta events), the analytics fan-out, and the config gate.
//
// These are pure-Dart: no Facebook SDK / platform channel is touched, so they
// verify the load-bearing logic (correct Meta event per source event, NO
// revenue double-firing, one-fire-per-event, error isolation) without a device.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/config/meta_config.dart';
import 'package:matheasy/core/monitoring/crash_reporting_service.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/features/analytics/application/age_gate_controller.dart';
import 'package:matheasy/features/analytics/application/analytics_service.dart';
import 'package:matheasy/features/analytics/application/composite_analytics_service.dart';
import 'package:matheasy/features/analytics/application/meta_analytics_service.dart';
import 'package:matheasy/features/analytics/domain/age_assurance.dart';
import 'package:matheasy/features/analytics/domain/analytics_event.dart';
import 'package:matheasy/features/analytics/domain/meta_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    test('is configured once the real App ID + Client Token are wired', () {
      expect(MetaConfig.isConfigured, isTrue);
      expect(MetaConfig.appId.startsWith('REPLACE_'), isFalse);
      expect(MetaConfig.clientToken.startsWith('REPLACE_'), isFalse);
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

  group('AgeAssurance (COPPA age gate)', () {
    test('classifies birth year against the current year', () {
      expect(
        assuranceForBirthYear(null, currentYear: 2026),
        AgeAssurance.unknown,
      );
      // age 13 → the threshold is inclusive.
      expect(
        assuranceForBirthYear(2013, currentYear: 2026),
        AgeAssurance.teenOrAdult,
      );
      // age 12 → child.
      expect(
        assuranceForBirthYear(2014, currentYear: 2026),
        AgeAssurance.child,
      );
      expect(
        assuranceForBirthYear(1990, currentYear: 2026),
        AgeAssurance.teenOrAdult,
      );
    });

    test(
      'implausible years fail closed to unknown (never unlock tracking)',
      () {
        expect(
          assuranceForBirthYear(2030, currentYear: 2026),
          AgeAssurance.unknown,
        );
        expect(
          assuranceForBirthYear(1800, currentYear: 2026),
          AgeAssurance.unknown,
        );
      },
    );

    test('only a confirmed teen/adult permits ad tracking', () {
      expect(AgeAssurance.teenOrAdult.adTrackingPermitted, isTrue);
      expect(AgeAssurance.child.adTrackingPermitted, isFalse);
      expect(AgeAssurance.unknown.adTrackingPermitted, isFalse);
    });
  });

  group('AgeGateController drives MetaSdk.trackingAllowed', () {
    tearDown(MetaSdk.reset);

    Future<ProviderContainer> containerWith(Map<String, Object> seed) async {
      SharedPreferences.setMockInitialValues(seed);
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('a confirmed adult unlocks tracking', () async {
      final year = DateTime.now().year - 30;
      final container = await containerWith({'privacy.birth_year': year});
      expect(
        container.read(ageGateControllerProvider),
        AgeAssurance.teenOrAdult,
      );
      expect(MetaSdk.trackingAllowed, isTrue);
    });

    test('a child keeps tracking OFF', () async {
      final year = DateTime.now().year - 8;
      final container = await containerWith({'privacy.birth_year': year});
      expect(container.read(ageGateControllerProvider), AgeAssurance.child);
      expect(MetaSdk.trackingAllowed, isFalse);
    });

    test(
      'unknown age fails closed and does not prompt while Meta is off',
      () async {
        final container = await containerWith({});
        expect(container.read(ageGateControllerProvider), AgeAssurance.unknown);
        expect(MetaSdk.trackingAllowed, isFalse);
        // Meta isn't configured in tests (MetaSdk.isReady == false) → never prompt.
        expect(
          container.read(ageGateControllerProvider.notifier).shouldPrompt,
          isFalse,
        );
      },
    );

    test('recording an adult birth year flips the gate on', () async {
      final container = await containerWith({});
      expect(MetaSdk.trackingAllowed, isFalse);
      await container
          .read(ageGateControllerProvider.notifier)
          .recordBirthYear(DateTime.now().year - 25);
      expect(
        container.read(ageGateControllerProvider),
        AgeAssurance.teenOrAdult,
      );
      expect(MetaSdk.trackingAllowed, isTrue);
    });
  });
}
