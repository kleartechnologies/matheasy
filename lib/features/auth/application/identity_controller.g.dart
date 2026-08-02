// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'identity_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Establishes and maintains this device's server identity — the client end of
/// the anti-abuse chain described in `docs/matheasy-anti-abuse-security.md`.
///
/// On launch, in order:
///   1. resolve the Firebase Installation ID (layer 1),
///   2. make sure a Firebase session exists at all, creating an ANONYMOUS one if
///      not (layer 2), so a brand-new install has an identity to meter against
///      before anybody signs in,
///   3. announce the installation under whichever account is now current,
///   4. pull the authoritative usage meter.
///
/// And on every account change afterwards — a restored session, an interactive
/// sign-in, a sign-out — it re-announces and re-reads.
///
/// None of this gates anything, blocks a frame, or surfaces an error. It is the
/// bookkeeping that lets the SERVER recognise a device across accounts; every
/// enforcement decision is made there, from the database, on the next metered
/// request. If all of it fails, the app behaves exactly as it did before this
/// layer existed.
///
/// Kept alive from the app root (mirrors [AnalyticsController]) so it is running
/// before the tab shell mounts.

@ProviderFor(IdentityController)
final identityControllerProvider = IdentityControllerProvider._();

/// Establishes and maintains this device's server identity — the client end of
/// the anti-abuse chain described in `docs/matheasy-anti-abuse-security.md`.
///
/// On launch, in order:
///   1. resolve the Firebase Installation ID (layer 1),
///   2. make sure a Firebase session exists at all, creating an ANONYMOUS one if
///      not (layer 2), so a brand-new install has an identity to meter against
///      before anybody signs in,
///   3. announce the installation under whichever account is now current,
///   4. pull the authoritative usage meter.
///
/// And on every account change afterwards — a restored session, an interactive
/// sign-in, a sign-out — it re-announces and re-reads.
///
/// None of this gates anything, blocks a frame, or surfaces an error. It is the
/// bookkeeping that lets the SERVER recognise a device across accounts; every
/// enforcement decision is made there, from the database, on the next metered
/// request. If all of it fails, the app behaves exactly as it did before this
/// layer existed.
///
/// Kept alive from the app root (mirrors [AnalyticsController]) so it is running
/// before the tab shell mounts.
final class IdentityControllerProvider
    extends $NotifierProvider<IdentityController, void> {
  /// Establishes and maintains this device's server identity — the client end of
  /// the anti-abuse chain described in `docs/matheasy-anti-abuse-security.md`.
  ///
  /// On launch, in order:
  ///   1. resolve the Firebase Installation ID (layer 1),
  ///   2. make sure a Firebase session exists at all, creating an ANONYMOUS one if
  ///      not (layer 2), so a brand-new install has an identity to meter against
  ///      before anybody signs in,
  ///   3. announce the installation under whichever account is now current,
  ///   4. pull the authoritative usage meter.
  ///
  /// And on every account change afterwards — a restored session, an interactive
  /// sign-in, a sign-out — it re-announces and re-reads.
  ///
  /// None of this gates anything, blocks a frame, or surfaces an error. It is the
  /// bookkeeping that lets the SERVER recognise a device across accounts; every
  /// enforcement decision is made there, from the database, on the next metered
  /// request. If all of it fails, the app behaves exactly as it did before this
  /// layer existed.
  ///
  /// Kept alive from the app root (mirrors [AnalyticsController]) so it is running
  /// before the tab shell mounts.
  IdentityControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'identityControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$identityControllerHash();

  @$internal
  @override
  IdentityController create() => IdentityController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$identityControllerHash() =>
    r'06180e6e02a291a697541680b4a6fddb2890ab32';

/// Establishes and maintains this device's server identity — the client end of
/// the anti-abuse chain described in `docs/matheasy-anti-abuse-security.md`.
///
/// On launch, in order:
///   1. resolve the Firebase Installation ID (layer 1),
///   2. make sure a Firebase session exists at all, creating an ANONYMOUS one if
///      not (layer 2), so a brand-new install has an identity to meter against
///      before anybody signs in,
///   3. announce the installation under whichever account is now current,
///   4. pull the authoritative usage meter.
///
/// And on every account change afterwards — a restored session, an interactive
/// sign-in, a sign-out — it re-announces and re-reads.
///
/// None of this gates anything, blocks a frame, or surfaces an error. It is the
/// bookkeeping that lets the SERVER recognise a device across accounts; every
/// enforcement decision is made there, from the database, on the next metered
/// request. If all of it fails, the app behaves exactly as it did before this
/// layer existed.
///
/// Kept alive from the app root (mirrors [AnalyticsController]) so it is running
/// before the tab shell mounts.

abstract class _$IdentityController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
