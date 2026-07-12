// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'result_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
///
/// Async by design so a future AI solver drops straight in — the screen already
/// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
/// so re-opening the same problem reuses the cached solution.

@ProviderFor(ResultController)
final resultControllerProvider = ResultControllerFamily._();

/// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
///
/// Async by design so a future AI solver drops straight in — the screen already
/// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
/// so re-opening the same problem reuses the cached solution.
final class ResultControllerProvider
    extends $AsyncNotifierProvider<ResultController, ResultData> {
  /// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
  ///
  /// Async by design so a future AI solver drops straight in — the screen already
  /// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
  /// so re-opening the same problem reuses the cached solution.
  ResultControllerProvider._({
    required ResultControllerFamily super.from,
    required DetectedEquation super.argument,
  }) : super(
         retry: null,
         name: r'resultControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$resultControllerHash();

  @override
  String toString() {
    return r'resultControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ResultController create() => ResultController();

  @override
  bool operator ==(Object other) {
    return other is ResultControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$resultControllerHash() => r'108d302b745ed9f02618e210b69028e0cc1d3283';

/// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
///
/// Async by design so a future AI solver drops straight in — the screen already
/// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
/// so re-opening the same problem reuses the cached solution.

final class ResultControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ResultController,
          AsyncValue<ResultData>,
          ResultData,
          FutureOr<ResultData>,
          DetectedEquation
        > {
  ResultControllerFamily._()
    : super(
        retry: null,
        name: r'resultControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
  ///
  /// Async by design so a future AI solver drops straight in — the screen already
  /// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
  /// so re-opening the same problem reuses the cached solution.

  ResultControllerProvider call(DetectedEquation equation) =>
      ResultControllerProvider._(argument: equation, from: this);

  @override
  String toString() => r'resultControllerProvider';
}

/// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
///
/// Async by design so a future AI solver drops straight in — the screen already
/// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
/// so re-opening the same problem reuses the cached solution.

abstract class _$ResultController extends $AsyncNotifier<ResultData> {
  late final _$args = ref.$arg as DetectedEquation;
  DetectedEquation get equation => _$args;

  FutureOr<ResultData> build(DetectedEquation equation);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<ResultData>, ResultData>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ResultData>, ResultData>,
              AsyncValue<ResultData>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}

/// Remembers the last selected result tab (kept alive). Re-visiting the same
/// problem restores the tab; opening a different problem resets to Solution so
/// a new answer always starts with its solution context.

@ProviderFor(ResultTab)
final resultTabProvider = ResultTabProvider._();

/// Remembers the last selected result tab (kept alive). Re-visiting the same
/// problem restores the tab; opening a different problem resets to Solution so
/// a new answer always starts with its solution context.
final class ResultTabProvider extends $NotifierProvider<ResultTab, int> {
  /// Remembers the last selected result tab (kept alive). Re-visiting the same
  /// problem restores the tab; opening a different problem resets to Solution so
  /// a new answer always starts with its solution context.
  ResultTabProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'resultTabProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$resultTabHash();

  @$internal
  @override
  ResultTab create() => ResultTab();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$resultTabHash() => r'411f9ff9df232bfdd9714fb70b11e47fe6dfa778';

/// Remembers the last selected result tab (kept alive). Re-visiting the same
/// problem restores the tab; opening a different problem resets to Solution so
/// a new answer always starts with its solution context.

abstract class _$ResultTab extends $Notifier<int> {
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
