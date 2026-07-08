// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usage_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The local usage ledger — records free-tier consumption of scans, Numi
/// messages and generated practice questions. Kept alive; hydrates on build and
/// persists every change fire-and-forget (mirrors `StatsController`).
///
/// This is the single mutator of [UsageCounts]; gating reads the derived
/// [usageSnapshotProvider], which folds these counts against the tier quota.
/// Counts still increment for Pro users (harmless — the snapshot reports
/// unlimited regardless), so a lapse back to free reflects real usage.

@ProviderFor(UsageController)
final usageControllerProvider = UsageControllerProvider._();

/// The local usage ledger — records free-tier consumption of scans, Numi
/// messages and generated practice questions. Kept alive; hydrates on build and
/// persists every change fire-and-forget (mirrors `StatsController`).
///
/// This is the single mutator of [UsageCounts]; gating reads the derived
/// [usageSnapshotProvider], which folds these counts against the tier quota.
/// Counts still increment for Pro users (harmless — the snapshot reports
/// unlimited regardless), so a lapse back to free reflects real usage.
final class UsageControllerProvider
    extends $NotifierProvider<UsageController, UsageCounts> {
  /// The local usage ledger — records free-tier consumption of scans, Numi
  /// messages and generated practice questions. Kept alive; hydrates on build and
  /// persists every change fire-and-forget (mirrors `StatsController`).
  ///
  /// This is the single mutator of [UsageCounts]; gating reads the derived
  /// [usageSnapshotProvider], which folds these counts against the tier quota.
  /// Counts still increment for Pro users (harmless — the snapshot reports
  /// unlimited regardless), so a lapse back to free reflects real usage.
  UsageControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'usageControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$usageControllerHash();

  @$internal
  @override
  UsageController create() => UsageController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UsageCounts value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UsageCounts>(value),
    );
  }
}

String _$usageControllerHash() => r'e42427647b68479e7b3290fd10dba09f878e377f';

/// The local usage ledger — records free-tier consumption of scans, Numi
/// messages and generated practice questions. Kept alive; hydrates on build and
/// persists every change fire-and-forget (mirrors `StatsController`).
///
/// This is the single mutator of [UsageCounts]; gating reads the derived
/// [usageSnapshotProvider], which folds these counts against the tier quota.
/// Counts still increment for Pro users (harmless — the snapshot reports
/// unlimited regardless), so a lapse back to free reflects real usage.

abstract class _$UsageController extends $Notifier<UsageCounts> {
  UsageCounts build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<UsageCounts, UsageCounts>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UsageCounts, UsageCounts>,
              UsageCounts,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The computed usage view the UI and gating consult. Reacts to both the counts
/// and the Pro entitlement, so the moment a purchase lands every gate reopens.

@ProviderFor(usageSnapshot)
final usageSnapshotProvider = UsageSnapshotProvider._();

/// The computed usage view the UI and gating consult. Reacts to both the counts
/// and the Pro entitlement, so the moment a purchase lands every gate reopens.

final class UsageSnapshotProvider
    extends $FunctionalProvider<UsageSnapshot, UsageSnapshot, UsageSnapshot>
    with $Provider<UsageSnapshot> {
  /// The computed usage view the UI and gating consult. Reacts to both the counts
  /// and the Pro entitlement, so the moment a purchase lands every gate reopens.
  UsageSnapshotProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'usageSnapshotProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$usageSnapshotHash();

  @$internal
  @override
  $ProviderElement<UsageSnapshot> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UsageSnapshot create(Ref ref) {
    return usageSnapshot(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UsageSnapshot value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UsageSnapshot>(value),
    );
  }
}

String _$usageSnapshotHash() => r'e2b652e0899fffd94d9f84e9dd84b9a8e2ac777d';
