// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Supplies the Home dashboard's data.
///
/// STAGE 3: entirely mock/in-memory — no backend, no persistence. It lightly
/// personalizes from the onboarding answers (weak topics + daily-goal target)
/// to show the layers connecting; a later stage swaps this for real data.

@ProviderFor(HomeController)
final homeControllerProvider = HomeControllerProvider._();

/// Supplies the Home dashboard's data.
///
/// STAGE 3: entirely mock/in-memory — no backend, no persistence. It lightly
/// personalizes from the onboarding answers (weak topics + daily-goal target)
/// to show the layers connecting; a later stage swaps this for real data.
final class HomeControllerProvider
    extends $NotifierProvider<HomeController, HomeData> {
  /// Supplies the Home dashboard's data.
  ///
  /// STAGE 3: entirely mock/in-memory — no backend, no persistence. It lightly
  /// personalizes from the onboarding answers (weak topics + daily-goal target)
  /// to show the layers connecting; a later stage swaps this for real data.
  HomeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'homeControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$homeControllerHash();

  @$internal
  @override
  HomeController create() => HomeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HomeData value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HomeData>(value),
    );
  }
}

String _$homeControllerHash() => r'b7f4c842cd2ba47348b27c13fc02bcb4e8a3b8c9';

/// Supplies the Home dashboard's data.
///
/// STAGE 3: entirely mock/in-memory — no backend, no persistence. It lightly
/// personalizes from the onboarding answers (weak topics + daily-goal target)
/// to show the layers connecting; a later stage swaps this for real data.

abstract class _$HomeController extends $Notifier<HomeData> {
  HomeData build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<HomeData, HomeData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HomeData, HomeData>,
              HomeData,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
