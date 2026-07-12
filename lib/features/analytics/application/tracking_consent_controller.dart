import 'dart:io' show Platform;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/monitoring/logging_service.dart';
import '../../subscription/application/subscription_service.dart';
import 'meta_analytics_service.dart';

part 'tracking_consent_controller.g.dart';

/// Runs the App Tracking Transparency (ATT) prompt and propagates the user's
/// decision to the ad SDKs. Driven by `AdConsentGate` **after** the COPPA age
/// gate confirms a 13+ user — never for under-13 / unknown-age users.
///
/// When permitted it: emits the Meta install/session signal ([MetaSdk.activateApp]),
/// enables Meta advertiser-id (IDFA) collection only when ATT is authorized, and
/// hands RevenueCat the Facebook anonymous id + device identifiers so
/// server-side purchase events attribute to the Meta ad click. A tracking denial
/// is honoured — no matching identifiers are shared.
@Riverpod(keepAlive: true)
class TrackingConsentController extends _$TrackingConsentController {
  bool _done = false;

  @override
  void build() {}

  /// Requests ATT (iOS) once, then syncs the decision to Meta + RevenueCat.
  /// A no-op unless Meta is configured (release only) AND the age gate has set
  /// [MetaSdk.trackingAllowed]. Runs at most once per launch.
  Future<void> requestIfNeeded() async {
    if (_done || !MetaSdk.isReady || !MetaSdk.trackingAllowed) return;
    _done = true;
    try {
      // Install/session signal — only now, once the age gate permits tracking.
      await MetaSdk.activateApp();

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
