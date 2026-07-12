import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:flutter/foundation.dart';

import '../../../core/config/meta_config.dart';
import '../../../core/monitoring/logging_service.dart';
import '../domain/analytics_event.dart';
import '../domain/meta_event.dart';
import 'analytics_service.dart';

/// Process-wide handle to the configured Facebook SDK, installed by
/// [initializeMetaAnalytics] in `bootstrap`. Exposes only the narrow operations
/// the tracking-consent flow needs, so `facebook_app_events` stays quarantined
/// to this file — mirroring how `purchases_flutter` lives only behind the
/// RevenueCat service.
class MetaSdk {
  const MetaSdk._();

  static FacebookAppEvents? _events;

  /// Whether the Facebook SDK is configured and installed this launch.
  static bool get isReady => _events != null;

  /// Installs the SDK handle. Called once from bootstrap.
  static void install(FacebookAppEvents events) => _events = events;

  /// Clears the handle — tests only.
  @visibleForTesting
  static void reset() => _events = null;

  /// Enables/disables collection of the device advertiser id (IDFA / GAID).
  /// Driven by the ATT decision on iOS; on Android it is subject to the AD_ID
  /// permission + the user's Google account settings.
  static Future<void> setAdvertiserIdCollectionEnabled(bool enabled) async =>
      _events?.setAdvertiserIdCollectionEnabled(enabled);

  /// The Facebook SDK's anonymous device id, handed to RevenueCat for
  /// server-side (Conversions API) purchase matching. Null when not ready.
  static Future<String?> anonymousId() async => _events?.getAnonymousId();
}

/// A Meta App Events [AnalyticsService] backend. Maps the app's [AnalyticsEvent]
/// taxonomy onto Meta events via [MetaEventMapper] and logs them through the
/// Facebook SDK.
///
/// Only constructed in release builds with real credentials (see
/// [initializeMetaAnalytics]), so it always forwards. Revenue events are never
/// logged here — [MetaEventMapper] drops them so RevenueCat's server-side
/// Conversions API stays the single source of truth for purchases (no double
/// counting in Ads Manager).
class MetaAnalyticsService implements AnalyticsService {
  MetaAnalyticsService(this._events);

  final FacebookAppEvents _events;

  @override
  Future<void> logEvent(AnalyticsEvent event) async {
    final meta = MetaEventMapper.map(event);
    if (meta == null) return;
    await _events.logEvent(
      name: meta.name,
      parameters: meta.parameters.isEmpty
          ? null
          : Map<String, dynamic>.from(meta.parameters),
    );
  }

  @override
  Future<void> setUserId(String? id) async {
    if (id == null) {
      await _events.clearUserID();
    } else {
      await _events.setUserID(id);
    }
  }

  @override
  Future<void> setUserProperty(String name, String? value) async {
    // Meta has no arbitrary user-property surface (unlike GA4). Intentionally a
    // no-op; coarse tiers reach Meta as events, not properties.
  }
}

/// One-time Meta/Facebook SDK initialization, called from `bootstrap`.
///
/// Returns a [MetaAnalyticsService] to compose into the analytics fan-out, or
/// `null` when Meta isn't configured (placeholder credentials) — in which case
/// the SDK is never touched and the app is unaffected.
///
/// The whole Meta layer is RELEASE-ONLY: in debug/profile it stays dormant (the
/// SDK is never touched, ATT never prompts, no identifiers are collected),
/// mirroring how Firebase Analytics collection is release-gated. QA the flow via
/// a TestFlight / internal-release build.
///
/// Privacy posture: advertiser-id (IDFA / GAID) collection stays OFF until the
/// user resolves App Tracking Transparency (see `TrackingConsentController`).
Future<MetaAnalyticsService?> initializeMetaAnalytics() async {
  if (!MetaConfig.isConfigured) {
    LoggingService.info(
      'Meta Ads not configured (placeholder App ID/Client Token) — Facebook SDK '
      'dormant. Paste real values into MetaConfig + the native plist/strings.',
    );
    return null;
  }
  if (!kReleaseMode) {
    LoggingService.info('Meta Ads disabled in debug/profile — release only.');
    return null;
  }
  try {
    final events = FacebookAppEvents();
    // Never collect the advertiser id before ATT authorizes it.
    await events.setAdvertiserIdCollectionEnabled(false);
    // Keep automatic app-event logging OFF: it also enables the SDK's implicit
    // in-app-purchase observer, which would DOUBLE-COUNT the purchases/trials
    // RevenueCat already sends server-side (Conversions API). We still emit the
    // install/session signal explicitly via activateApp() — install campaigns
    // need it and it carries no purchase or advertiser-id data.
    await events.setAutoLogAppEventsEnabled(false);
    await events.activateApp();
    MetaSdk.install(events);
    return MetaAnalyticsService(events);
  } catch (error, stack) {
    LoggingService.error(
      'Meta Ads initialization failed — Facebook SDK disabled',
      error: error,
      stackTrace: stack,
    );
    return null;
  }
}
