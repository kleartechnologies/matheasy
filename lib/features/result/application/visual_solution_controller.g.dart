// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'visual_solution_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Generates the [VisualSolution] for a solved problem via the
/// [VisualSolutionService].
///
/// Lazy by design: it only builds when the (Pro-unlocked) Visual tab first
/// renders, so free users and untouched tabs never spend an AI call. Keyed by
/// the equation like [ResultController], so revisiting the same problem reuses
/// the cached visual. Waits for the solver first so the walkthrough always
/// agrees with the Solution tab's answer.

@ProviderFor(VisualSolutionController)
final visualSolutionControllerProvider = VisualSolutionControllerFamily._();

/// Generates the [VisualSolution] for a solved problem via the
/// [VisualSolutionService].
///
/// Lazy by design: it only builds when the (Pro-unlocked) Visual tab first
/// renders, so free users and untouched tabs never spend an AI call. Keyed by
/// the equation like [ResultController], so revisiting the same problem reuses
/// the cached visual. Waits for the solver first so the walkthrough always
/// agrees with the Solution tab's answer.
final class VisualSolutionControllerProvider
    extends $AsyncNotifierProvider<VisualSolutionController, VisualSolution> {
  /// Generates the [VisualSolution] for a solved problem via the
  /// [VisualSolutionService].
  ///
  /// Lazy by design: it only builds when the (Pro-unlocked) Visual tab first
  /// renders, so free users and untouched tabs never spend an AI call. Keyed by
  /// the equation like [ResultController], so revisiting the same problem reuses
  /// the cached visual. Waits for the solver first so the walkthrough always
  /// agrees with the Solution tab's answer.
  VisualSolutionControllerProvider._({
    required VisualSolutionControllerFamily super.from,
    required DetectedEquation super.argument,
  }) : super(
         retry: _noRetry,
         name: r'visualSolutionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$visualSolutionControllerHash();

  @override
  String toString() {
    return r'visualSolutionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  VisualSolutionController create() => VisualSolutionController();

  @override
  bool operator ==(Object other) {
    return other is VisualSolutionControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$visualSolutionControllerHash() =>
    r'ffb20c20883bc1730d5e2207066fd629210e6982';

/// Generates the [VisualSolution] for a solved problem via the
/// [VisualSolutionService].
///
/// Lazy by design: it only builds when the (Pro-unlocked) Visual tab first
/// renders, so free users and untouched tabs never spend an AI call. Keyed by
/// the equation like [ResultController], so revisiting the same problem reuses
/// the cached visual. Waits for the solver first so the walkthrough always
/// agrees with the Solution tab's answer.

final class VisualSolutionControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          VisualSolutionController,
          AsyncValue<VisualSolution>,
          VisualSolution,
          FutureOr<VisualSolution>,
          DetectedEquation
        > {
  VisualSolutionControllerFamily._()
    : super(
        retry: _noRetry,
        name: r'visualSolutionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Generates the [VisualSolution] for a solved problem via the
  /// [VisualSolutionService].
  ///
  /// Lazy by design: it only builds when the (Pro-unlocked) Visual tab first
  /// renders, so free users and untouched tabs never spend an AI call. Keyed by
  /// the equation like [ResultController], so revisiting the same problem reuses
  /// the cached visual. Waits for the solver first so the walkthrough always
  /// agrees with the Solution tab's answer.

  VisualSolutionControllerProvider call(DetectedEquation equation) =>
      VisualSolutionControllerProvider._(argument: equation, from: this);

  @override
  String toString() => r'visualSolutionControllerProvider';
}

/// Generates the [VisualSolution] for a solved problem via the
/// [VisualSolutionService].
///
/// Lazy by design: it only builds when the (Pro-unlocked) Visual tab first
/// renders, so free users and untouched tabs never spend an AI call. Keyed by
/// the equation like [ResultController], so revisiting the same problem reuses
/// the cached visual. Waits for the solver first so the walkthrough always
/// agrees with the Solution tab's answer.

abstract class _$VisualSolutionController
    extends $AsyncNotifier<VisualSolution> {
  late final _$args = ref.$arg as DetectedEquation;
  DetectedEquation get equation => _$args;

  FutureOr<VisualSolution> build(DetectedEquation equation);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<VisualSolution>, VisualSolution>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<VisualSolution>, VisualSolution>,
              AsyncValue<VisualSolution>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

/// Records teaser impressions for the locked Visual tab — once per problem,
/// mirroring how `PaywallController.markViewed` keeps analytics out of
/// widgets. The teaser calls [markShown] post-frame.

@ProviderFor(VisualTeaserTracker)
final visualTeaserTrackerProvider = VisualTeaserTrackerProvider._();

/// Records teaser impressions for the locked Visual tab — once per problem,
/// mirroring how `PaywallController.markViewed` keeps analytics out of
/// widgets. The teaser calls [markShown] post-frame.
final class VisualTeaserTrackerProvider
    extends $NotifierProvider<VisualTeaserTracker, int> {
  /// Records teaser impressions for the locked Visual tab — once per problem,
  /// mirroring how `PaywallController.markViewed` keeps analytics out of
  /// widgets. The teaser calls [markShown] post-frame.
  VisualTeaserTrackerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'visualTeaserTrackerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$visualTeaserTrackerHash();

  @$internal
  @override
  VisualTeaserTracker create() => VisualTeaserTracker();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$visualTeaserTrackerHash() =>
    r'6b2de0cc8f873d79bc1eb19000e2383e453269bd';

/// Records teaser impressions for the locked Visual tab — once per problem,
/// mirroring how `PaywallController.markViewed` keeps analytics out of
/// widgets. The teaser calls [markShown] post-frame.

abstract class _$VisualTeaserTracker extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
