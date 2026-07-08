import 'package:flutter/foundation.dart';

/// A single analytics event: a GA4-safe snake_case [name] plus optional
/// [parameters] (string/num values only, per the Firebase Analytics contract).
///
/// Events are constructed via the named factories below so the taxonomy lives in
/// one place and call sites can't invent ad-hoc event names. No PII is ever put
/// in parameters — only enums, counts and coarse categories.
@immutable
class AnalyticsEvent {
  const AnalyticsEvent(this.name, [this.parameters = const {}]);

  final String name;
  final Map<String, Object> parameters;

  // ---- Lifecycle ----
  factory AnalyticsEvent.appOpened() => const AnalyticsEvent('app_opened');

  factory AnalyticsEvent.onboardingCompleted() =>
      const AnalyticsEvent('onboarding_completed');

  factory AnalyticsEvent.accountCreated({required String provider}) =>
      AnalyticsEvent('account_created', {'provider': provider});

  // ---- Scan ----
  factory AnalyticsEvent.scanStarted({required String source}) =>
      AnalyticsEvent('scan_started', {'source': source});

  factory AnalyticsEvent.scanCompleted() =>
      const AnalyticsEvent('scan_completed');

  factory AnalyticsEvent.resultViewed({required String problemType}) =>
      AnalyticsEvent('result_viewed', {'problem_type': problemType});

  // ---- Tutor ----
  factory AnalyticsEvent.tutorOpened() => const AnalyticsEvent('tutor_opened');

  factory AnalyticsEvent.tutorMessageSent() =>
      const AnalyticsEvent('tutor_message_sent');

  // ---- Practice ----
  factory AnalyticsEvent.practiceStarted({required String topic}) =>
      AnalyticsEvent('practice_started', {'topic': topic});

  factory AnalyticsEvent.practiceCompleted({
    required int correct,
    required int total,
  }) =>
      AnalyticsEvent('practice_completed', {'correct': correct, 'total': total});

  // ---- Progress ----
  factory AnalyticsEvent.achievementUnlocked({required String id}) =>
      AnalyticsEvent('achievement_unlocked', {'achievement_id': id});

  // ---- Monetization ----
  factory AnalyticsEvent.paywallViewed({required String trigger}) =>
      AnalyticsEvent('paywall_viewed', {'trigger': trigger});

  factory AnalyticsEvent.subscriptionPurchased({required String plan}) =>
      AnalyticsEvent('subscription_purchased', {'plan': plan});

  factory AnalyticsEvent.subscriptionRestored() =>
      const AnalyticsEvent('subscription_restored');

  // ---- Profile / Sync ----
  factory AnalyticsEvent.profileEdited() =>
      const AnalyticsEvent('profile_edited');

  factory AnalyticsEvent.syncCompleted({
    required int downloaded,
    required int uploaded,
  }) =>
      AnalyticsEvent(
        'sync_completed',
        {'downloaded': downloaded, 'uploaded': uploaded},
      );

  @override
  bool operator ==(Object other) =>
      other is AnalyticsEvent &&
      other.name == name &&
      mapEquals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(parameters.entries));

  @override
  String toString() => 'AnalyticsEvent($name, $parameters)';
}
