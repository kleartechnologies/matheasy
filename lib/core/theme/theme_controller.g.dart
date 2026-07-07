// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'theme_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Controls the app-wide [ThemeMode].
///
/// Stage 0 keeps this in memory only; a later stage will persist the choice
/// (SharedPreferences / Isar) and hydrate it on launch.

@ProviderFor(ThemeModeController)
final themeModeControllerProvider = ThemeModeControllerProvider._();

/// Controls the app-wide [ThemeMode].
///
/// Stage 0 keeps this in memory only; a later stage will persist the choice
/// (SharedPreferences / Isar) and hydrate it on launch.
final class ThemeModeControllerProvider
    extends $NotifierProvider<ThemeModeController, ThemeMode> {
  /// Controls the app-wide [ThemeMode].
  ///
  /// Stage 0 keeps this in memory only; a later stage will persist the choice
  /// (SharedPreferences / Isar) and hydrate it on launch.
  ThemeModeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'themeModeControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$themeModeControllerHash();

  @$internal
  @override
  ThemeModeController create() => ThemeModeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ThemeMode value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ThemeMode>(value),
    );
  }
}

String _$themeModeControllerHash() =>
    r'de48f108d223422a9471f11f97858212e46ea64b';

/// Controls the app-wide [ThemeMode].
///
/// Stage 0 keeps this in memory only; a later stage will persist the choice
/// (SharedPreferences / Isar) and hydrate it on launch.

abstract class _$ThemeModeController extends $Notifier<ThemeMode> {
  ThemeMode build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ThemeMode, ThemeMode>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ThemeMode, ThemeMode>,
              ThemeMode,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
