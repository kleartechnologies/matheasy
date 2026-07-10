// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Assembles the Progress dashboard from practice progress, local analytics,
/// achievements and the signed-in user. Recomputes whenever any of those change.

@ProviderFor(ProgressController)
final progressControllerProvider = ProgressControllerProvider._();

/// Assembles the Progress dashboard from practice progress, local analytics,
/// achievements and the signed-in user. Recomputes whenever any of those change.
final class ProgressControllerProvider
    extends $NotifierProvider<ProgressController, ProgressOverview> {
  /// Assembles the Progress dashboard from practice progress, local analytics,
  /// achievements and the signed-in user. Recomputes whenever any of those change.
  ProgressControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'progressControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$progressControllerHash();

  @$internal
  @override
  ProgressController create() => ProgressController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProgressOverview value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProgressOverview>(value),
    );
  }
}

String _$progressControllerHash() =>
    r'ef6e0d2ccbc0c861bbf7e7858d148eaaeea61e59';

/// Assembles the Progress dashboard from practice progress, local analytics,
/// achievements and the signed-in user. Recomputes whenever any of those change.

abstract class _$ProgressController extends $Notifier<ProgressOverview> {
  ProgressOverview build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ProgressOverview, ProgressOverview>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProgressOverview, ProgressOverview>,
              ProgressOverview,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
