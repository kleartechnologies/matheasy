// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_session.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the user has completed onboarding.
///
/// STAGE 7: persisted locally via [PreferencesStore] and hydrated on launch, so
/// returning users skip straight past onboarding.

@ProviderFor(OnboardingController)
final onboardingControllerProvider = OnboardingControllerProvider._();

/// Whether the user has completed onboarding.
///
/// STAGE 7: persisted locally via [PreferencesStore] and hydrated on launch, so
/// returning users skip straight past onboarding.
final class OnboardingControllerProvider
    extends $NotifierProvider<OnboardingController, bool> {
  /// Whether the user has completed onboarding.
  ///
  /// STAGE 7: persisted locally via [PreferencesStore] and hydrated on launch, so
  /// returning users skip straight past onboarding.
  OnboardingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingControllerHash();

  @$internal
  @override
  OnboardingController create() => OnboardingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$onboardingControllerHash() =>
    r'86bb1fe730f737fe1601079febe7163592a97eb0';

/// Whether the user has completed onboarding.
///
/// STAGE 7: persisted locally via [PreferencesStore] and hydrated on launch, so
/// returning users skip straight past onboarding.

abstract class _$OnboardingController extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
