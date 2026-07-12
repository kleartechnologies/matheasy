import 'package:flutter/foundation.dart';

import 'analytics_event.dart';

/// A single Facebook/Meta App Event to log: a canonical event [name] plus
/// optional [parameters]. Values are `String`/`num`/`bool` only, per the Meta
/// SDK contract (mirrors [AnalyticsEvent]).
///
/// This is a plain value object with no plugin dependency, so the mapping in
/// [MetaEventMapper] is fully unit-testable.
@immutable
class MetaEvent {
  const MetaEvent(this.name, [this.parameters = const {}]);

  final String name;
  final Map<String, Object> parameters;

  @override
  bool operator ==(Object other) =>
      other is MetaEvent &&
      other.name == name &&
      mapEquals(other.parameters, parameters);

  @override
  int get hashCode => Object.hash(
    name,
    // Order-independent + value-based, to stay consistent with `mapEquals` in
    // `==` (MapEntry has no value equality, so hashAll(entries) would not).
    Object.hashAllUnordered(
      parameters.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  @override
  String toString() => 'MetaEvent($name, $parameters)';
}

/// Canonical Meta App Event names (the literal wire strings the Facebook SDK
/// emits) and standard parameter keys, plus Matheasy's custom event names.
///
/// Standard events are preferred for App Event Optimization (AEO); custom
/// events are used where no standard event fits. Revenue events are deliberately
/// ABSENT — purchases/trials/renewals are delivered to Meta server-side by
/// RevenueCat's Conversions API to avoid double counting (see [MetaEventMapper]).
class MetaEventNames {
  const MetaEventNames._();

  // ---- Meta standard events ----
  static const String completeRegistration = 'fb_mobile_complete_registration';
  static const String viewContent = 'fb_mobile_content_view';
  static const String completeTutorial = 'fb_mobile_tutorial_completion';

  // ---- Matheasy custom events ----
  static const String firstScan = 'FirstScan';
  static const String visualLearningOpened = 'VisualLearningOpened';
  static const String practiceStarted = 'PracticeStarted';
  static const String practiceCompleted = 'PracticeCompleted';
  static const String aiTutorOpened = 'AITutorOpened';
  static const String paywallViewed = 'PaywallViewed';
  static const String subscriptionRestored = 'SubscriptionRestored';

  // ---- Standard parameter keys ----
  static const String paramContentType = 'fb_content_type';
  static const String paramRegistrationMethod = 'fb_registration_method';
}

/// Translates an [AnalyticsEvent] (the app's product taxonomy) into the Meta
/// App Event to forward, or `null` when the event should NOT reach Meta.
///
/// Design rules:
///   * Each source event maps to AT MOST ONE Meta event — no duplicate firing.
///   * The mapping is the single seam between the app taxonomy and Meta, so
///     call sites never learn Meta event names.
///   * Revenue events (`subscription_purchased`) return `null`: Meta receives
///     purchases/trials/renewals server-side via RevenueCat's Conversions API
///     (mapped to the `Subscribe` / `StartTrial` / `Purchase` standard events).
///     Logging them client-side too would double-count revenue in Ads Manager.
class MetaEventMapper {
  const MetaEventMapper._();

  static MetaEvent? map(AnalyticsEvent event) {
    switch (event.name) {
      // Sign up / login (interactive auth only — a silent restore never emits
      // `account_created`). Meta doesn't distinguish the two; both are a
      // registration completion for AEO's top-of-funnel event.
      case 'account_created':
        final provider = event.parameters['provider'];
        return MetaEvent(MetaEventNames.completeRegistration, {
          MetaEventNames.paramRegistrationMethod: ?provider,
        });

      // Onboarding completion — a natural "activation" (CompleteTutorial) event.
      case 'onboarding_completed':
        return const MetaEvent(MetaEventNames.completeTutorial);

      // First Scan — the `firstScan` achievement fires exactly once, on the
      // user's first scan; other achievements are not forwarded to Meta.
      case 'achievement_unlocked':
        return event.parameters['achievement_id'] == 'firstScan'
            ? const MetaEvent(MetaEventNames.firstScan)
            : null;

      // Problem solved / answer viewed → ViewContent, keyed by problem type.
      case 'result_viewed':
        final problemType = event.parameters['problem_type'];
        return MetaEvent(MetaEventNames.viewContent, {
          MetaEventNames.paramContentType: ?problemType,
        });

      case 'visual_viewed':
        return const MetaEvent(MetaEventNames.visualLearningOpened);

      case 'tutor_opened':
        return const MetaEvent(MetaEventNames.aiTutorOpened);

      case 'practice_started':
        return const MetaEvent(MetaEventNames.practiceStarted);

      case 'practice_completed':
        return MetaEvent(MetaEventNames.practiceCompleted, {
          ...event.parameters, // correct / total
        });

      // Paywall impression → a custom PaywallViewed event, NOT the standard
      // InitiateCheckout: the paywall auto-opens on scan/tutor/practice limits,
      // so an impression is not checkout intent and must not inflate that
      // standard funnel event. AEO can still optimize toward custom events.
      case 'paywall_viewed':
        return const MetaEvent(MetaEventNames.paywallViewed);

      // Restore is not a revenue event, so it is safe to log client-side.
      case 'subscription_restored':
        return const MetaEvent(MetaEventNames.subscriptionRestored);

      // Not forwarded to Meta:
      //   * subscription_purchased — revenue, owned by RevenueCat CAPI.
      //   * app_opened — the SDK's auto session/`activateApp` already covers it.
      //   * scan_started/completed, recognition_*, question_*, mastery_*,
      //     sync_completed, profile_edited, etc. — internal/product analytics
      //     that would only add noise to the ad account.
      default:
        return null;
    }
  }
}
