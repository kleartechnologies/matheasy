// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paywall_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives the paywall: loads live products, tracks the selected plan and runs
/// the purchase/restore flow through [SubscriptionController].
///
/// Auto-disposes with the paywall route, so every open starts fresh with the
/// annual plan preselected and re-fetches the latest prices.

@ProviderFor(PaywallController)
final paywallControllerProvider = PaywallControllerProvider._();

/// Drives the paywall: loads live products, tracks the selected plan and runs
/// the purchase/restore flow through [SubscriptionController].
///
/// Auto-disposes with the paywall route, so every open starts fresh with the
/// annual plan preselected and re-fetches the latest prices.
final class PaywallControllerProvider
    extends $NotifierProvider<PaywallController, PaywallState> {
  /// Drives the paywall: loads live products, tracks the selected plan and runs
  /// the purchase/restore flow through [SubscriptionController].
  ///
  /// Auto-disposes with the paywall route, so every open starts fresh with the
  /// annual plan preselected and re-fetches the latest prices.
  PaywallControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'paywallControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$paywallControllerHash();

  @$internal
  @override
  PaywallController create() => PaywallController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PaywallState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PaywallState>(value),
    );
  }
}

String _$paywallControllerHash() => r'3e5b976878c1d1bcbd8088e1087a1e1254ae762f';

/// Drives the paywall: loads live products, tracks the selected plan and runs
/// the purchase/restore flow through [SubscriptionController].
///
/// Auto-disposes with the paywall route, so every open starts fresh with the
/// annual plan preselected and re-fetches the latest prices.

abstract class _$PaywallController extends $Notifier<PaywallState> {
  PaywallState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<PaywallState, PaywallState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PaywallState, PaywallState>,
              PaywallState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
