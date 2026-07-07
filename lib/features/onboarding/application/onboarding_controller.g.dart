// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the answers collected during the onboarding flow.
///
/// STAGE 2: in-memory only (no persistence, no Firebase). A later stage saves
/// [OnboardingData] and consumes it to personalize the app. This is distinct
/// from the session-level `OnboardingController` (a bool "completed" flag used
/// by the navigation guard).

@ProviderFor(OnboardingFlowController)
final onboardingFlowControllerProvider = OnboardingFlowControllerProvider._();

/// Holds the answers collected during the onboarding flow.
///
/// STAGE 2: in-memory only (no persistence, no Firebase). A later stage saves
/// [OnboardingData] and consumes it to personalize the app. This is distinct
/// from the session-level `OnboardingController` (a bool "completed" flag used
/// by the navigation guard).
final class OnboardingFlowControllerProvider
    extends $NotifierProvider<OnboardingFlowController, OnboardingData> {
  /// Holds the answers collected during the onboarding flow.
  ///
  /// STAGE 2: in-memory only (no persistence, no Firebase). A later stage saves
  /// [OnboardingData] and consumes it to personalize the app. This is distinct
  /// from the session-level `OnboardingController` (a bool "completed" flag used
  /// by the navigation guard).
  OnboardingFlowControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingFlowControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingFlowControllerHash();

  @$internal
  @override
  OnboardingFlowController create() => OnboardingFlowController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnboardingData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnboardingData>(value),
    );
  }
}

String _$onboardingFlowControllerHash() =>
    r'f39359231e3b83273c14a2c13d67eda66e7dc883';

/// Holds the answers collected during the onboarding flow.
///
/// STAGE 2: in-memory only (no persistence, no Firebase). A later stage saves
/// [OnboardingData] and consumes it to personalize the app. This is distinct
/// from the session-level `OnboardingController` (a bool "completed" flag used
/// by the navigation guard).

abstract class _$OnboardingFlowController extends $Notifier<OnboardingData> {
  OnboardingData build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<OnboardingData, OnboardingData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OnboardingData, OnboardingData>,
              OnboardingData,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
