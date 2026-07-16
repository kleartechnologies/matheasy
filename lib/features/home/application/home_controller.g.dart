// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'home_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Supplies Home's data — derived entirely from REAL per-user state, never a
/// mock.
///
/// Identity comes from [profileControllerProvider] (the SAME source the greeting
/// avatar reads, so name + avatar always agree). Because that provider
/// transitively watches `currentUserProvider`, Home rebuilds across the
/// sign-in / sign-up boundary — that reactive dependency is the whole fix for
/// "Home shows the previous/demo user after signup".
///
/// Learning state (streak, weak topics, daily-challenge completion, first-day)
/// comes from [practiceProgressControllerProvider]. A brand-new account gets an
/// HONEST first-day Home — 'Learner', zeros, hidden cards — never a fabricated
/// streak or accuracy.

@ProviderFor(HomeController)
final homeControllerProvider = HomeControllerProvider._();

/// Supplies Home's data — derived entirely from REAL per-user state, never a
/// mock.
///
/// Identity comes from [profileControllerProvider] (the SAME source the greeting
/// avatar reads, so name + avatar always agree). Because that provider
/// transitively watches `currentUserProvider`, Home rebuilds across the
/// sign-in / sign-up boundary — that reactive dependency is the whole fix for
/// "Home shows the previous/demo user after signup".
///
/// Learning state (streak, weak topics, daily-challenge completion, first-day)
/// comes from [practiceProgressControllerProvider]. A brand-new account gets an
/// HONEST first-day Home — 'Learner', zeros, hidden cards — never a fabricated
/// streak or accuracy.
final class HomeControllerProvider
    extends $NotifierProvider<HomeController, HomeData> {
  /// Supplies Home's data — derived entirely from REAL per-user state, never a
  /// mock.
  ///
  /// Identity comes from [profileControllerProvider] (the SAME source the greeting
  /// avatar reads, so name + avatar always agree). Because that provider
  /// transitively watches `currentUserProvider`, Home rebuilds across the
  /// sign-in / sign-up boundary — that reactive dependency is the whole fix for
  /// "Home shows the previous/demo user after signup".
  ///
  /// Learning state (streak, weak topics, daily-challenge completion, first-day)
  /// comes from [practiceProgressControllerProvider]. A brand-new account gets an
  /// HONEST first-day Home — 'Learner', zeros, hidden cards — never a fabricated
  /// streak or accuracy.
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

String _$homeControllerHash() => r'c54d19ab296ed33b95297c6becec90fa8e1f9043';

/// Supplies Home's data — derived entirely from REAL per-user state, never a
/// mock.
///
/// Identity comes from [profileControllerProvider] (the SAME source the greeting
/// avatar reads, so name + avatar always agree). Because that provider
/// transitively watches `currentUserProvider`, Home rebuilds across the
/// sign-in / sign-up boundary — that reactive dependency is the whole fix for
/// "Home shows the previous/demo user after signup".
///
/// Learning state (streak, weak topics, daily-challenge completion, first-day)
/// comes from [practiceProgressControllerProvider]. A brand-new account gets an
/// HONEST first-day Home — 'Learner', zeros, hidden cards — never a fabricated
/// streak or accuracy.

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
