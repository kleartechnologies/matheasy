// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_usage_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the server's authoritative meter, or `null` before one has been read.
///
/// The local [UsageController] keeps counting optimistically — it is what makes
/// the meter move the instant a scan completes, offline included. This provider
/// is the correction on top of it: the number the server will actually enforce,
/// fetched at launch and after every sign-in.
///
/// The two are folded together in `usageSnapshotProvider` by taking the larger
/// of each counter, which is what makes a wiped preferences file, a reinstall or
/// a brand-new Google account show the usage the server already remembers
/// instead of a hopeful zero.
///
/// Nothing here decides anything. `usage/guard.ts` does, from the database, on
/// every metered request.

@ProviderFor(ServerUsageController)
final serverUsageControllerProvider = ServerUsageControllerProvider._();

/// Holds the server's authoritative meter, or `null` before one has been read.
///
/// The local [UsageController] keeps counting optimistically — it is what makes
/// the meter move the instant a scan completes, offline included. This provider
/// is the correction on top of it: the number the server will actually enforce,
/// fetched at launch and after every sign-in.
///
/// The two are folded together in `usageSnapshotProvider` by taking the larger
/// of each counter, which is what makes a wiped preferences file, a reinstall or
/// a brand-new Google account show the usage the server already remembers
/// instead of a hopeful zero.
///
/// Nothing here decides anything. `usage/guard.ts` does, from the database, on
/// every metered request.
final class ServerUsageControllerProvider
    extends $NotifierProvider<ServerUsageController, ServerUsage?> {
  /// Holds the server's authoritative meter, or `null` before one has been read.
  ///
  /// The local [UsageController] keeps counting optimistically — it is what makes
  /// the meter move the instant a scan completes, offline included. This provider
  /// is the correction on top of it: the number the server will actually enforce,
  /// fetched at launch and after every sign-in.
  ///
  /// The two are folded together in `usageSnapshotProvider` by taking the larger
  /// of each counter, which is what makes a wiped preferences file, a reinstall or
  /// a brand-new Google account show the usage the server already remembers
  /// instead of a hopeful zero.
  ///
  /// Nothing here decides anything. `usage/guard.ts` does, from the database, on
  /// every metered request.
  ServerUsageControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverUsageControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverUsageControllerHash();

  @$internal
  @override
  ServerUsageController create() => ServerUsageController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ServerUsage? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ServerUsage?>(value),
    );
  }
}

String _$serverUsageControllerHash() =>
    r'6de260e7795bd26eaf74974f02b6278e091ce504';

/// Holds the server's authoritative meter, or `null` before one has been read.
///
/// The local [UsageController] keeps counting optimistically — it is what makes
/// the meter move the instant a scan completes, offline included. This provider
/// is the correction on top of it: the number the server will actually enforce,
/// fetched at launch and after every sign-in.
///
/// The two are folded together in `usageSnapshotProvider` by taking the larger
/// of each counter, which is what makes a wiped preferences file, a reinstall or
/// a brand-new Google account show the usage the server already remembers
/// instead of a hopeful zero.
///
/// Nothing here decides anything. `usage/guard.ts` does, from the database, on
/// every metered request.

abstract class _$ServerUsageController extends $Notifier<ServerUsage?> {
  ServerUsage? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ServerUsage?, ServerUsage?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ServerUsage?, ServerUsage?>,
              ServerUsage?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
