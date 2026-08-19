import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/monitoring/logging_service.dart';
import '../../subscription/application/subscription_service.dart';
import 'meta_analytics_service.dart';

part 'tracking_consent_controller.g.dart';

/// Runs the App Tracking Transparency (ATT) prompt and propagates the user's
/// decision to the ad SDKs. Driven by `AdConsentGate` **after** the COPPA age
/// gate confirms a 13+ user — never for under-13 / unknown-age users — and
/// re-entrant from Settings → Privacy → "Ad tracking".
///
/// Ordering is not negotiable (App Review guideline 2.1): the ATT request is
/// the FIRST thing that happens. Only once the user has answered do we emit the
/// Meta install/session signal ([MetaSdk.activateApp]), enable Meta
/// advertiser-id (IDFA) collection — authorized users only — and hand
/// RevenueCat the Facebook anonymous id + device identifiers so server-side
/// purchase events attribute to the Meta ad click. A tracking denial is
/// honoured: no matching identifiers are shared.
@Riverpod(keepAlive: true)
class TrackingConsentController extends _$TrackingConsentController {
  /// Guards against two overlapping requests (the launch gate and a Settings
  /// tap racing). Cleared as soon as the decision is applied.
  bool _requesting = false;

  /// Whether the once-per-launch Meta install/session ping already fired.
  bool _activated = false;

  @override
  void build() {}

  /// The device's ATT decision, read WITHOUT presenting the prompt.
  /// [TrackingStatus.notSupported] on Android and on iOS < 14.
  Future<TrackingStatus> currentStatus() async {
    try {
      return await AppTrackingTransparency.trackingAuthorizationStatus;
    } catch (error, stack) {
      LoggingService.error(
        'Reading ATT status failed',
        error: error,
        stackTrace: stack,
      );
      return TrackingStatus.notSupported;
    }
  }

  /// Requests ATT, then syncs the decision to Meta + RevenueCat.
  ///
  /// Deliberately safe to call repeatedly — on every launch, and again from
  /// Settings. iOS presents the system dialog only while the status is
  /// `notDetermined`; afterwards it replays the existing decision without a
  /// second prompt. That makes the flow SELF-HEALING: a user (or an App Review
  /// tester) whose first launch was interrupted is asked again next time
  /// instead of being stranded on a device that can never show the prompt.
  ///
  /// Not gated on [MetaSdk.isReady]: whether the Facebook SDK happened to
  /// initialise this launch must never decide whether the user is asked for
  /// consent. It IS gated on [MetaSdk.trackingAllowed] — the COPPA age gate.
  Future<TrackingStatus> requestIfNeeded() async {
    if (!MetaSdk.trackingAllowed) return currentStatus();
    if (_requesting) return currentStatus();
    _requesting = true;
    try {
      // ATT FIRST. Nothing that could be used to track the user may run before
      // the decision — `activateApp()` posts an install/session event to
      // graph.facebook.com, so it waits below.
      final status = Platform.isIOS
          ? await AppTrackingTransparency.requestTrackingAuthorization()
          : TrackingStatus.notSupported;
      await _applyDecision(status);
      return status;
    } catch (error, stack) {
      LoggingService.error(
        'Tracking-consent sync failed',
        error: error,
        stackTrace: stack,
      );
      return TrackingStatus.notSupported;
    } finally {
      _requesting = false;
    }
  }

  /// Propagates a resolved ATT decision to the ad SDKs. A no-op when the
  /// Facebook SDK isn't installed this launch (debug/profile, or a failed
  /// init) — the user was still asked, there is simply nothing to tell.
  Future<void> _applyDecision(TrackingStatus status) async {
    if (!MetaSdk.isReady) return;

    // Android has no ATT; advertiser-id collection there is gated by the
    // AD_ID permission + the user's Google account settings.
    final authorized = Platform.isIOS
        ? status == TrackingStatus.authorized
        : true;

    await MetaSdk.setAdvertiserIdCollectionEnabled(authorized);

    // Install/session signal — once per launch, and only after the user has
    // answered ATT.
    if (!_activated) {
      _activated = true;
      await MetaSdk.activateApp();
    }

    // Honour a tracking denial: only hand the ad-network matching identifiers
    // to RevenueCat (→ Meta Conversions API) when the user authorized it.
    if (authorized) {
      final fbAnonymousId = await MetaSdk.anonymousId();
      await ref
          .read(subscriptionServiceProvider)
          .attachAdAttribution(fbAnonymousId: fbAnonymousId);
    }
  }
}
