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
/// Reactive: rebuilds when the signed-in user, aggregated progress, or the
/// saved editable profile changes (the editable slice is WATCHED via
/// [editableProfileControllerProvider], so every rename propagates here and
/// to every other watcher — the Progress screen included).

@ProviderFor(ProfileController)
final profileControllerProvider = ProfileControllerProvider._();

/// Assembles the [ProfileView] the Profile screen renders — identity (auth),
/// editable fields (name + avatar) and headline stats (progress) — and owns the
/// profile-scoped account actions (edit, sign out, delete).
///
/// Reactive: rebuilds when the signed-in user, aggregated progress, or the
/// saved editable profile changes (the editable slice is WATCHED via
/// [editableProfileControllerProvider], so every rename propagates here and
/// to every other watcher — the Progress screen included).
final class ProfileControllerProvider
    extends $NotifierProvider<ProfileController, ProfileView> {
  /// Assembles the [ProfileView] the Profile screen renders — identity (auth),
  /// editable fields (name + avatar) and headline stats (progress) — and owns the
  /// profile-scoped account actions (edit, sign out, delete).
  ///
  /// Reactive: rebuilds when the signed-in user, aggregated progress, or the
  /// saved editable profile changes (the editable slice is WATCHED via
  /// [editableProfileControllerProvider], so every rename propagates here and
  /// to every other watcher — the Progress screen included).
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

String _$profileControllerHash() => r'2c295127d87c259aa5e826846bb947731f369729';

/// Assembles the [ProfileView] the Profile screen renders — identity (auth),
/// editable fields (name + avatar) and headline stats (progress) — and owns the
/// profile-scoped account actions (edit, sign out, delete).
///
/// Reactive: rebuilds when the signed-in user, aggregated progress, or the
/// saved editable profile changes (the editable slice is WATCHED via
/// [editableProfileControllerProvider], so every rename propagates here and
/// to every other watcher — the Progress screen included).

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
