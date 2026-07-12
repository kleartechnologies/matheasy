// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The solved-problem history — hydrates from the local cache on build and is
/// the single mutator of the on-device list. Kept alive so the recent-problems
/// surfaces (Home, History screen) share one live copy.
///
/// Mutations persist through [HistoryRepository] *before* the state notifies, so
/// the offline-first sync layer — which observes this controller — sees a
/// consistent local store when it debounces an upload.

@ProviderFor(HistoryController)
final historyControllerProvider = HistoryControllerProvider._();

/// The solved-problem history — hydrates from the local cache on build and is
/// the single mutator of the on-device list. Kept alive so the recent-problems
/// surfaces (Home, History screen) share one live copy.
///
/// Mutations persist through [HistoryRepository] *before* the state notifies, so
/// the offline-first sync layer — which observes this controller — sees a
/// consistent local store when it debounces an upload.
final class HistoryControllerProvider
    extends $NotifierProvider<HistoryController, List<HistoryEntry>> {
  /// The solved-problem history — hydrates from the local cache on build and is
  /// the single mutator of the on-device list. Kept alive so the recent-problems
  /// surfaces (Home, History screen) share one live copy.
  ///
  /// Mutations persist through [HistoryRepository] *before* the state notifies, so
  /// the offline-first sync layer — which observes this controller — sees a
  /// consistent local store when it debounces an upload.
  HistoryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'historyControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$historyControllerHash();

  @$internal
  @override
  HistoryController create() => HistoryController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<HistoryEntry> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<HistoryEntry>>(value),
    );
  }
}

String _$historyControllerHash() => r'9e012bb803ed1c93a9539d10e63c4a00b8ddd818';

/// The solved-problem history — hydrates from the local cache on build and is
/// the single mutator of the on-device list. Kept alive so the recent-problems
/// surfaces (Home, History screen) share one live copy.
///
/// Mutations persist through [HistoryRepository] *before* the state notifies, so
/// the offline-first sync layer — which observes this controller — sees a
/// consistent local store when it debounces an upload.

abstract class _$HistoryController extends $Notifier<List<HistoryEntry>> {
  List<HistoryEntry> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<List<HistoryEntry>, List<HistoryEntry>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<HistoryEntry>, List<HistoryEntry>>,
              List<HistoryEntry>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
