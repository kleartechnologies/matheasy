// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_consent_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Runs the App Tracking Transparency (ATT) prompt and propagates the user's
/// decision to the ad SDKs. Driven by `AdConsentGate` **after** the COPPA age
/// gate confirms a 13+ user — never for under-13 / unknown-age users.
///
/// When permitted it: emits the Meta install/session signal ([MetaSdk.activateApp]),
/// enables Meta advertiser-id (IDFA) collection only when ATT is authorized, and
/// hands RevenueCat the Facebook anonymous id + device identifiers so
/// server-side purchase events attribute to the Meta ad click. A tracking denial
/// is honoured — no matching identifiers are shared.

@ProviderFor(TrackingConsentController)
final trackingConsentControllerProvider = TrackingConsentControllerProvider._();

/// Runs the App Tracking Transparency (ATT) prompt and propagates the user's
/// decision to the ad SDKs. Driven by `AdConsentGate` **after** the COPPA age
/// gate confirms a 13+ user — never for under-13 / unknown-age users.
///
/// When permitted it: emits the Meta install/session signal ([MetaSdk.activateApp]),
/// enables Meta advertiser-id (IDFA) collection only when ATT is authorized, and
/// hands RevenueCat the Facebook anonymous id + device identifiers so
/// server-side purchase events attribute to the Meta ad click. A tracking denial
/// is honoured — no matching identifiers are shared.
final class TrackingConsentControllerProvider
    extends $NotifierProvider<TrackingConsentController, void> {
  /// Runs the App Tracking Transparency (ATT) prompt and propagates the user's
  /// decision to the ad SDKs. Driven by `AdConsentGate` **after** the COPPA age
  /// gate confirms a 13+ user — never for under-13 / unknown-age users.
  ///
  /// When permitted it: emits the Meta install/session signal ([MetaSdk.activateApp]),
  /// enables Meta advertiser-id (IDFA) collection only when ATT is authorized, and
  /// hands RevenueCat the Facebook anonymous id + device identifiers so
  /// server-side purchase events attribute to the Meta ad click. A tracking denial
  /// is honoured — no matching identifiers are shared.
  TrackingConsentControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trackingConsentControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trackingConsentControllerHash();

  @$internal
  @override
  TrackingConsentController create() => TrackingConsentController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$trackingConsentControllerHash() =>
    r'daf21bd3cae6bfff09533fff4b8f9a0d029020fa';

/// Runs the App Tracking Transparency (ATT) prompt and propagates the user's
/// decision to the ad SDKs. Driven by `AdConsentGate` **after** the COPPA age
/// gate confirms a 13+ user — never for under-13 / unknown-age users.
///
/// When permitted it: emits the Meta install/session signal ([MetaSdk.activateApp]),
/// enables Meta advertiser-id (IDFA) collection only when ATT is authorized, and
/// hands RevenueCat the Facebook anonymous id + device identifiers so
/// server-side purchase events attribute to the Meta ad click. A tracking denial
/// is honoured — no matching identifiers are shared.

abstract class _$TrackingConsentController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
