// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profile_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Assembles the [ProfileView] the Profile screen renders — identity (auth),
/// editable fields (name + avatar) and headline stats (progress) — and owns the
/// profile-scoped account actions (edit, sign out, delete).
///
/// Reactive: rebuilds when the signed-in user or aggregated progress changes,
/// re-reading the persisted editable profile each time (so it always reflects
/// the latest saved override).

@ProviderFor(ProfileController)
final profileControllerProvider = ProfileControllerProvider._();

/// Assembles the [ProfileView] the Profile screen renders — identity (auth),
/// editable fields (name + avatar) and headline stats (progress) — and owns the
/// profile-scoped account actions (edit, sign out, delete).
///
/// Reactive: rebuilds when the signed-in user or aggregated progress changes,
/// re-reading the persisted editable profile each time (so it always reflects
/// the latest saved override).
final class ProfileControllerProvider
    extends $NotifierProvider<ProfileController, ProfileView> {
  /// Assembles the [ProfileView] the Profile screen renders — identity (auth),
  /// editable fields (name + avatar) and headline stats (progress) — and owns the
  /// profile-scoped account actions (edit, sign out, delete).
  ///
  /// Reactive: rebuilds when the signed-in user or aggregated progress changes,
  /// re-reading the persisted editable profile each time (so it always reflects
  /// the latest saved override).
  ProfileControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'profileControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$profileControllerHash();

  @$internal
  @override
  ProfileController create() => ProfileController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProfileView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProfileView>(value),
    );
  }
}

String _$profileControllerHash() => r'344b642f2a6a72ec2a6903940cf42eae9e275d2c';

/// Assembles the [ProfileView] the Profile screen renders — identity (auth),
/// editable fields (name + avatar) and headline stats (progress) — and owns the
/// profile-scoped account actions (edit, sign out, delete).
///
/// Reactive: rebuilds when the signed-in user or aggregated progress changes,
/// re-reading the persisted editable profile each time (so it always reflects
/// the latest saved override).

abstract class _$ProfileController extends $Notifier<ProfileView> {
  ProfileView build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ProfileView, ProfileView>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProfileView, ProfileView>,
              ProfileView,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
