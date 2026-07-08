// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stats_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The local analytics store — records scans, tutor usage, learning days and the
/// recent-activity feed. Kept alive; hydrates on build and persists on change.
///
/// This is the single mutator of [ProgressStats]; the achievement engine and
/// progress dashboard read from it.

@ProviderFor(StatsController)
final statsControllerProvider = StatsControllerProvider._();

/// The local analytics store — records scans, tutor usage, learning days and the
/// recent-activity feed. Kept alive; hydrates on build and persists on change.
///
/// This is the single mutator of [ProgressStats]; the achievement engine and
/// progress dashboard read from it.
final class StatsControllerProvider
    extends $NotifierProvider<StatsController, ProgressStats> {
  /// The local analytics store — records scans, tutor usage, learning days and the
  /// recent-activity feed. Kept alive; hydrates on build and persists on change.
  ///
  /// This is the single mutator of [ProgressStats]; the achievement engine and
  /// progress dashboard read from it.
  StatsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statsControllerHash();

  @$internal
  @override
  StatsController create() => StatsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProgressStats value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProgressStats>(value),
    );
  }
}

String _$statsControllerHash() => r'348444637045250435488c37167c40a003be96f1';

/// The local analytics store — records scans, tutor usage, learning days and the
/// recent-activity feed. Kept alive; hydrates on build and persists on change.
///
/// This is the single mutator of [ProgressStats]; the achievement engine and
/// progress dashboard read from it.

abstract class _$StatsController extends $Notifier<ProgressStats> {
  ProgressStats build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ProgressStats, ProgressStats>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProgressStats, ProgressStats>,
              ProgressStats,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
