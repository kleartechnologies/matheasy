// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The offline-first sync orchestrator.
///
/// Keeps the local store as the source of truth and mirrors it to the cloud:
/// * observes every synced controller and, on a *real* local change, debounces
///   an upload (authenticated users only — guests stay local);
/// * on sign-in / launch, runs a full reconcile (download → merge → upload) and
///   refreshes the controllers whose local copy changed;
/// * exposes a manual "sync now" and a cloud wipe for account deletion.
///
/// Controllers are never modified — they don't know the cloud exists.

@ProviderFor(SyncController)
final syncControllerProvider = SyncControllerProvider._();

/// The offline-first sync orchestrator.
///
/// Keeps the local store as the source of truth and mirrors it to the cloud:
/// * observes every synced controller and, on a *real* local change, debounces
///   an upload (authenticated users only — guests stay local);
/// * on sign-in / launch, runs a full reconcile (download → merge → upload) and
///   refreshes the controllers whose local copy changed;
/// * exposes a manual "sync now" and a cloud wipe for account deletion.
///
/// Controllers are never modified — they don't know the cloud exists.
final class SyncControllerProvider
    extends $NotifierProvider<SyncController, SyncState> {
  /// The offline-first sync orchestrator.
  ///
  /// Keeps the local store as the source of truth and mirrors it to the cloud:
  /// * observes every synced controller and, on a *real* local change, debounces
  ///   an upload (authenticated users only — guests stay local);
  /// * on sign-in / launch, runs a full reconcile (download → merge → upload) and
  ///   refreshes the controllers whose local copy changed;
  /// * exposes a manual "sync now" and a cloud wipe for account deletion.
  ///
  /// Controllers are never modified — they don't know the cloud exists.
  SyncControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncControllerHash();

  @$internal
  @override
  SyncController create() => SyncController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncState>(value),
    );
  }
}

String _$syncControllerHash() => r'a48cbc90e6f78ed3a03e2cadd7b84c7859279ced';

/// The offline-first sync orchestrator.
///
/// Keeps the local store as the source of truth and mirrors it to the cloud:
/// * observes every synced controller and, on a *real* local change, debounces
///   an upload (authenticated users only — guests stay local);
/// * on sign-in / launch, runs a full reconcile (download → merge → upload) and
///   refreshes the controllers whose local copy changed;
/// * exposes a manual "sync now" and a cloud wipe for account deletion.
///
/// Controllers are never modified — they don't know the cloud exists.

abstract class _$SyncController extends $Notifier<SyncState> {
  SyncState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SyncState, SyncState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SyncState, SyncState>,
              SyncState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
