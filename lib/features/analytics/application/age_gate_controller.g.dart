// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'age_gate_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The COPPA age gate for ad tracking. Reads the persisted birth year, classifies
/// the user, and drives [MetaSdk.trackingAllowed] — the single flag every Meta
/// code path checks. Kept alive so the decision survives navigation.
///
/// Fails closed: an unknown age keeps tracking OFF, so no ad data reaches Meta
/// until a 13+ user is confirmed.

@ProviderFor(AgeGateController)
final ageGateControllerProvider = AgeGateControllerProvider._();

/// The COPPA age gate for ad tracking. Reads the persisted birth year, classifies
/// the user, and drives [MetaSdk.trackingAllowed] — the single flag every Meta
/// code path checks. Kept alive so the decision survives navigation.
///
/// Fails closed: an unknown age keeps tracking OFF, so no ad data reaches Meta
/// until a 13+ user is confirmed.
final class AgeGateControllerProvider
    extends $NotifierProvider<AgeGateController, AgeAssurance> {
  /// The COPPA age gate for ad tracking. Reads the persisted birth year, classifies
  /// the user, and drives [MetaSdk.trackingAllowed] — the single flag every Meta
  /// code path checks. Kept alive so the decision survives navigation.
  ///
  /// Fails closed: an unknown age keeps tracking OFF, so no ad data reaches Meta
  /// until a 13+ user is confirmed.
  AgeGateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ageGateControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ageGateControllerHash();

  @$internal
  @override
  AgeGateController create() => AgeGateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AgeAssurance value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AgeAssurance>(value),
    );
  }
}

String _$ageGateControllerHash() => r'ed68a5f000ad94e02b45381973b47556e553e993';

/// The COPPA age gate for ad tracking. Reads the persisted birth year, classifies
/// the user, and drives [MetaSdk.trackingAllowed] — the single flag every Meta
/// code path checks. Kept alive so the decision survives navigation.
///
/// Fails closed: an unknown age keeps tracking OFF, so no ad data reaches Meta
/// until a 13+ user is confirmed.

abstract class _$AgeGateController extends $Notifier<AgeAssurance> {
  AgeAssurance build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AgeAssurance, AgeAssurance>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AgeAssurance, AgeAssurance>,
              AgeAssurance,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
