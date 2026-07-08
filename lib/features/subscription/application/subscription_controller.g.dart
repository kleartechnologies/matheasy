// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'subscription_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The single source of truth for the user's subscription entitlement.
///
/// Subscribes to the [SubscriptionService]'s status stream (RevenueCat, or the
/// offline fallback) and projects it into a [SubscriptionStatus]. Kept alive for
/// the whole app so the entitlement survives navigation and the router can gate
/// on it. Seeds synchronously from the service's cached status so the first
/// frame already reflects the last-known plan.

@ProviderFor(SubscriptionController)
final subscriptionControllerProvider = SubscriptionControllerProvider._();

/// The single source of truth for the user's subscription entitlement.
///
/// Subscribes to the [SubscriptionService]'s status stream (RevenueCat, or the
/// offline fallback) and projects it into a [SubscriptionStatus]. Kept alive for
/// the whole app so the entitlement survives navigation and the router can gate
/// on it. Seeds synchronously from the service's cached status so the first
/// frame already reflects the last-known plan.
final class SubscriptionControllerProvider
    extends $NotifierProvider<SubscriptionController, SubscriptionStatus> {
  /// The single source of truth for the user's subscription entitlement.
  ///
  /// Subscribes to the [SubscriptionService]'s status stream (RevenueCat, or the
  /// offline fallback) and projects it into a [SubscriptionStatus]. Kept alive for
  /// the whole app so the entitlement survives navigation and the router can gate
  /// on it. Seeds synchronously from the service's cached status so the first
  /// frame already reflects the last-known plan.
  SubscriptionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'subscriptionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$subscriptionControllerHash();

  @$internal
  @override
  SubscriptionController create() => SubscriptionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SubscriptionStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SubscriptionStatus>(value),
    );
  }
}

String _$subscriptionControllerHash() =>
    r'e5eab8135c68b5d55034885416c87076bc4b9081';

/// The single source of truth for the user's subscription entitlement.
///
/// Subscribes to the [SubscriptionService]'s status stream (RevenueCat, or the
/// offline fallback) and projects it into a [SubscriptionStatus]. Kept alive for
/// the whole app so the entitlement survives navigation and the router can gate
/// on it. Seeds synchronously from the service's cached status so the first
/// frame already reflects the last-known plan.

abstract class _$SubscriptionController extends $Notifier<SubscriptionStatus> {
  SubscriptionStatus build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SubscriptionStatus, SubscriptionStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SubscriptionStatus, SubscriptionStatus>,
              SubscriptionStatus,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Whether the user holds the active `pro` entitlement — the app-wide gate the
/// router and premium-only features read. Replaces the Stage 1 placeholder
/// `PremiumController`; now sourced from RevenueCat.

@ProviderFor(isPro)
final isProProvider = IsProProvider._();

/// Whether the user holds the active `pro` entitlement — the app-wide gate the
/// router and premium-only features read. Replaces the Stage 1 placeholder
/// `PremiumController`; now sourced from RevenueCat.

final class IsProProvider extends $FunctionalProvider<bool, bool, bool>
    with $Provider<bool> {
  /// Whether the user holds the active `pro` entitlement — the app-wide gate the
  /// router and premium-only features read. Replaces the Stage 1 placeholder
  /// `PremiumController`; now sourced from RevenueCat.
  IsProProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'isProProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$isProHash();

  @$internal
  @override
  $ProviderElement<bool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  bool create(Ref ref) {
    return isPro(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$isProHash() => r'9ee55b339fd65cd765f162f517940286feb7c8ba';
