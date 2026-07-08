// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The single source of truth for every locally-persisted setting.
///
/// Hydrates synchronously from [SettingsRepository] on launch (SharedPreferences
/// is preloaded in bootstrap) and persists every change fire-and-forget, so the
/// UI updates instantly. `MatheasyApp` reads [ProfileSettings.appearance] and
/// [ProfileSettings.accessibility] from here to drive the theme and root
/// MediaQuery.

@ProviderFor(SettingsController)
final settingsControllerProvider = SettingsControllerProvider._();

/// The single source of truth for every locally-persisted setting.
///
/// Hydrates synchronously from [SettingsRepository] on launch (SharedPreferences
/// is preloaded in bootstrap) and persists every change fire-and-forget, so the
/// UI updates instantly. `MatheasyApp` reads [ProfileSettings.appearance] and
/// [ProfileSettings.accessibility] from here to drive the theme and root
/// MediaQuery.
final class SettingsControllerProvider
    extends $NotifierProvider<SettingsController, ProfileSettings> {
  /// The single source of truth for every locally-persisted setting.
  ///
  /// Hydrates synchronously from [SettingsRepository] on launch (SharedPreferences
  /// is preloaded in bootstrap) and persists every change fire-and-forget, so the
  /// UI updates instantly. `MatheasyApp` reads [ProfileSettings.appearance] and
  /// [ProfileSettings.accessibility] from here to drive the theme and root
  /// MediaQuery.
  SettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'settingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$settingsControllerHash();

  @$internal
  @override
  SettingsController create() => SettingsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ProfileSettings value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ProfileSettings>(value),
    );
  }
}

String _$settingsControllerHash() =>
    r'b07262bbe503e01a2bfee19063f49bfd89efe87a';

/// The single source of truth for every locally-persisted setting.
///
/// Hydrates synchronously from [SettingsRepository] on launch (SharedPreferences
/// is preloaded in bootstrap) and persists every change fire-and-forget, so the
/// UI updates instantly. `MatheasyApp` reads [ProfileSettings.appearance] and
/// [ProfileSettings.accessibility] from here to drive the theme and root
/// MediaQuery.

abstract class _$SettingsController extends $Notifier<ProfileSettings> {
  ProfileSettings build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ProfileSettings, ProfileSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ProfileSettings, ProfileSettings>,
              ProfileSettings,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
