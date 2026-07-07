// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_lifecycle.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracks the app's [AppLifecycleState] and exposes it to the rest of the app.
///
/// Keeping this in a provider lets any feature react to
/// foreground/background transitions (pause a camera, stop polling, refresh
/// data on resume, flush analytics on pause) without each screen wiring its own
/// observer. Watched once in the shell to keep it alive for the session.

@ProviderFor(AppLifecycle)
final appLifecycleProvider = AppLifecycleProvider._();

/// Tracks the app's [AppLifecycleState] and exposes it to the rest of the app.
///
/// Keeping this in a provider lets any feature react to
/// foreground/background transitions (pause a camera, stop polling, refresh
/// data on resume, flush analytics on pause) without each screen wiring its own
/// observer. Watched once in the shell to keep it alive for the session.
final class AppLifecycleProvider
    extends $NotifierProvider<AppLifecycle, AppLifecycleState> {
  /// Tracks the app's [AppLifecycleState] and exposes it to the rest of the app.
  ///
  /// Keeping this in a provider lets any feature react to
  /// foreground/background transitions (pause a camera, stop polling, refresh
  /// data on resume, flush analytics on pause) without each screen wiring its own
  /// observer. Watched once in the shell to keep it alive for the session.
  AppLifecycleProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appLifecycleProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appLifecycleHash();

  @$internal
  @override
  AppLifecycle create() => AppLifecycle();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppLifecycleState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppLifecycleState>(value),
    );
  }
}

String _$appLifecycleHash() => r'ae373e4079cc953060b7196fc572978931a2c52d';

/// Tracks the app's [AppLifecycleState] and exposes it to the rest of the app.
///
/// Keeping this in a provider lets any feature react to
/// foreground/background transitions (pause a camera, stop polling, refresh
/// data on resume, flush analytics on pause) without each screen wiring its own
/// observer. Watched once in the shell to keep it alive for the session.

abstract class _$AppLifecycle extends $Notifier<AppLifecycleState> {
  AppLifecycleState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AppLifecycleState, AppLifecycleState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AppLifecycleState, AppLifecycleState>,
              AppLifecycleState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
