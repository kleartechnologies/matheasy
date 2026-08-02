// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'usage_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The local usage ledger — records free-tier consumption of scans, AI tutor
/// messages and generated practice questions. Kept alive; hydrates on build and
/// persists every change fire-and-forget (mirrors `StatsController`).
///
/// This is the single mutator of [UsageCounts]; gating reads the derived
/// [usageSnapshotProvider], which folds these counts against the tier quota.
/// Counts still increment for Pro users (harmless — the snapshot reports
/// unlimited regardless), so a lapse back to free reflects real usage.

@ProviderFor(UsageController)
final usageControllerProvider = UsageControllerProvider._();

/// The local usage ledger — records free-tier consumption of scans, AI tutor
/// messages and generated practice questions. Kept alive; hydrates on build and
/// persists every change fire-and-forget (mirrors `StatsController`).
///
/// This is the single mutator of [UsageCounts]; gating reads the derived
/// [usageSnapshotProvider], which folds these counts against the tier quota.
/// Counts still increment for Pro users (harmless — the snapshot reports
/// unlimited regardless), so a lapse back to free reflects real usage.
final class UsageControllerProvider
    extends $NotifierProvider<UsageController, UsageCounts> {
  /// The local usage ledger — records free-tier consumption of scans, AI tutor
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

String _$usageControllerHash() => r'682342201898e5cb34c72a66aba8948d22480ee5';

/// The local usage ledger — records free-tier consumption of scans, AI tutor
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

/// The computed usage view the UI and gating consult. Reacts to the counts, the
/// Pro entitlement and the server's meter, so the moment a purchase lands every
/// gate reopens — and the moment the server's number arrives, the meter tells
/// the truth.
///
/// The server's view wins where the two disagree, in the only direction that is
/// safe to be wrong in:
///
///  * **counts** — the LARGER of local and server. The server's figure is the
///    effective one (max across this account and this installation), so a fresh
///    account on a spent device, a reinstall or a cleared preferences file shows
///    the usage that will actually be enforced rather than a hopeful zero. Local
///    can still be ahead of it between a scan and the next refresh, and that is
///    why it is a max and not an adoption.
///  * **quota** — the server's live Remote Config limits when known, so the
///    ceiling can be tuned without shipping a build. `UsageQuota.free` is the
///    compiled fallback.
///  * **isPro** — either source saying yes is yes. RevenueCat's local cache is
///    fresher right after a purchase; the server's is fresher after a renewal or
///    a grace period. Being generous here is a UX call only — the server still
///    refuses anything the entitlement doesn't cover.
///
/// This remains PRESENTATION. Every real decision is re-made in
/// `functions/src/usage/guard.ts`, from the database, on the next request.

@ProviderFor(usageSnapshot)
final usageSnapshotProvider = UsageSnapshotProvider._();

/// The computed usage view the UI and gating consult. Reacts to the counts, the
/// Pro entitlement and the server's meter, so the moment a purchase lands every
/// gate reopens — and the moment the server's number arrives, the meter tells
/// the truth.
///
/// The server's view wins where the two disagree, in the only direction that is
/// safe to be wrong in:
///
///  * **counts** — the LARGER of local and server. The server's figure is the
///    effective one (max across this account and this installation), so a fresh
///    account on a spent device, a reinstall or a cleared preferences file shows
///    the usage that will actually be enforced rather than a hopeful zero. Local
///    can still be ahead of it between a scan and the next refresh, and that is
///    why it is a max and not an adoption.
///  * **quota** — the server's live Remote Config limits when known, so the
///    ceiling can be tuned without shipping a build. `UsageQuota.free` is the
///    compiled fallback.
///  * **isPro** — either source saying yes is yes. RevenueCat's local cache is
///    fresher right after a purchase; the server's is fresher after a renewal or
///    a grace period. Being generous here is a UX call only — the server still
///    refuses anything the entitlement doesn't cover.
///
/// This remains PRESENTATION. Every real decision is re-made in
/// `functions/src/usage/guard.ts`, from the database, on the next request.

final class UsageSnapshotProvider
    extends $FunctionalProvider<UsageSnapshot, UsageSnapshot, UsageSnapshot>
    with $Provider<UsageSnapshot> {
  /// The computed usage view the UI and gating consult. Reacts to the counts, the
  /// Pro entitlement and the server's meter, so the moment a purchase lands every
  /// gate reopens — and the moment the server's number arrives, the meter tells
  /// the truth.
  ///
  /// The server's view wins where the two disagree, in the only direction that is
  /// safe to be wrong in:
  ///
  ///  * **counts** — the LARGER of local and server. The server's figure is the
  ///    effective one (max across this account and this installation), so a fresh
  ///    account on a spent device, a reinstall or a cleared preferences file shows
  ///    the usage that will actually be enforced rather than a hopeful zero. Local
  ///    can still be ahead of it between a scan and the next refresh, and that is
  ///    why it is a max and not an adoption.
  ///  * **quota** — the server's live Remote Config limits when known, so the
  ///    ceiling can be tuned without shipping a build. `UsageQuota.free` is the
  ///    compiled fallback.
  ///  * **isPro** — either source saying yes is yes. RevenueCat's local cache is
  ///    fresher right after a purchase; the server's is fresher after a renewal or
  ///    a grace period. Being generous here is a UX call only — the server still
  ///    refuses anything the entitlement doesn't cover.
  ///
  /// This remains PRESENTATION. Every real decision is re-made in
  /// `functions/src/usage/guard.ts`, from the database, on the next request.
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

String _$usageSnapshotHash() => r'd0715d7bff13847624d4c2cf4d71ea4cc748db63';
