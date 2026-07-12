// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_consent_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(TrackingConsentController)
final trackingConsentControllerProvider = TrackingConsentControllerProvider._();

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
final class TrackingConsentControllerProvider
    extends $NotifierProvider<TrackingConsentController, void> {
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
    r'c5347f377932f3c0b628058b71ba4eed55100b46';

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
