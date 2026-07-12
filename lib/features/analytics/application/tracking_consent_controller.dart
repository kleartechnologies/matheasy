import 'dart:async';
import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/widgets.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/monitoring/logging_service.dart';
import '../../subscription/application/subscription_service.dart';
import 'meta_analytics_service.dart';

part 'tracking_consent_controller.g.dart';

/// Orchestrates the App Tracking Transparency (ATT) prompt and propagates the
/// user's decision to the ad SDKs.
///
/// TRIGGER POINT (best practice): kept alive and watched by `AppShell`, so it
/// runs the first time the user reaches the main app — NEVER during launch or
/// the first frame, where Apple silently no-ops the prompt. A post-frame
/// callback defers the request until the app is foreground/active. It is only
/// meaningful once Meta is configured, so it no-ops otherwise (and on a fresh,
/// unconfigured checkout it never prompts).
///
/// On the ATT result it:
///   * enables Meta advertiser-id (IDFA) collection only when authorized, and
///   * hands RevenueCat the Facebook anonymous id + device identifiers so
///     server-side purchase events attribute to the Meta ad click.
///
/// Recommendation: for higher opt-in, move the [requestIfNeeded] call to just
/// after the user's first solved problem (the "aha" moment) — this controller
/// is the single seam, so only the call site changes.
@Riverpod(keepAlive: true)
class TrackingConsentController extends _$TrackingConsentController {
  bool _done = false;

  @override
  void build() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(requestIfNeeded()),
    );
  }

  /// Requests ATT (iOS) once, then syncs the decision to Meta + RevenueCat.
  /// Safe to call repeatedly — it runs at most once per launch, and is a no-op
  /// until Meta is configured (release builds only — [MetaSdk.isReady] is false
  /// in debug/profile).
  ///
  /// COPPA / minors: Matheasy can serve minors. This flow enables ad
  /// attribution for whoever reaches the app. If the app is child-directed or
  /// has actual knowledge of under-13 users, GATE this call behind an age check
  /// (skip it for those users) — behavioural ad tracking of children is
  /// prohibited regardless of the ATT answer. See the integration doc.
  Future<void> requestIfNeeded() async {
    if (_done || !MetaSdk.isReady) return;
    _done = true;
    try {
      // Android has no ATT; advertiser-id collection there is gated by the
      // AD_ID permission + the user's Google account settings.
      final authorized = Platform.isIOS ? await _requestAtt() : true;

      await MetaSdk.setAdvertiserIdCollectionEnabled(authorized);

      // Honour a tracking denial: only hand the ad-network matching identifiers
      // to RevenueCat (→ Meta Conversions API) when the user authorized it.
      if (authorized) {
        final fbAnonymousId = await MetaSdk.anonymousId();
        await ref
            .read(subscriptionServiceProvider)
            .attachAdAttribution(fbAnonymousId: fbAnonymousId);
      }
    } catch (error, stack) {
      LoggingService.error(
        'Tracking-consent sync failed',
        error: error,
        stackTrace: stack,
      );
    }
  }

  /// Presents the ATT dialog (only if the user hasn't decided yet; otherwise it
  /// returns the existing decision without a second prompt) and reports whether
  /// tracking was authorized.
  Future<bool> _requestAtt() async {
    final status = await AppTrackingTransparency.requestTrackingAuthorization();
    return status == TrackingStatus.authorized;
  }
}
