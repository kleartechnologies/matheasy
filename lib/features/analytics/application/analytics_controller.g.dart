// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'analytics_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Emits the analytics events derivable purely from app state, so no widget has
/// to. Kept alive from the app root ([MatheasyApp]) — NOT the shell — so it is
/// observing during onboarding and auth, before the tab shell mounts.
///
/// Observes: app open (once), onboarding completed, achievements unlocked, and
/// keeps the analytics user id + subscription tier in sync. `account_created`
/// is emitted from the interactive sign-in path in [AuthController] (a session
/// *restore* must not count as a new account), and the action/lifecycle events
/// (scan, tutor, practice, paywall, purchase, profile, sync) are emitted by
/// their own controllers via [analyticsServiceProvider].

@ProviderFor(AnalyticsController)
final analyticsControllerProvider = AnalyticsControllerProvider._();

/// Emits the analytics events derivable purely from app state, so no widget has
/// to. Kept alive from the app root ([MatheasyApp]) — NOT the shell — so it is
/// observing during onboarding and auth, before the tab shell mounts.
///
/// Observes: app open (once), onboarding completed, achievements unlocked, and
/// keeps the analytics user id + subscription tier in sync. `account_created`
/// is emitted from the interactive sign-in path in [AuthController] (a session
/// *restore* must not count as a new account), and the action/lifecycle events
/// (scan, tutor, practice, paywall, purchase, profile, sync) are emitted by
/// their own controllers via [analyticsServiceProvider].
final class AnalyticsControllerProvider
    extends $NotifierProvider<AnalyticsController, void> {
  /// Emits the analytics events derivable purely from app state, so no widget has
  /// to. Kept alive from the app root ([MatheasyApp]) — NOT the shell — so it is
  /// observing during onboarding and auth, before the tab shell mounts.
  ///
  /// Observes: app open (once), onboarding completed, achievements unlocked, and
  /// keeps the analytics user id + subscription tier in sync. `account_created`
  /// is emitted from the interactive sign-in path in [AuthController] (a session
  /// *restore* must not count as a new account), and the action/lifecycle events
  /// (scan, tutor, practice, paywall, purchase, profile, sync) are emitted by
  /// their own controllers via [analyticsServiceProvider].
  AnalyticsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'analyticsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$analyticsControllerHash();

  @$internal
  @override
  AnalyticsController create() => AnalyticsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$analyticsControllerHash() =>
    r'451bb1b95adf30298f41d91078cd60e0b517e067';

/// Emits the analytics events derivable purely from app state, so no widget has
/// to. Kept alive from the app root ([MatheasyApp]) — NOT the shell — so it is
/// observing during onboarding and auth, before the tab shell mounts.
///
/// Observes: app open (once), onboarding completed, achievements unlocked, and
/// keeps the analytics user id + subscription tier in sync. `account_created`
/// is emitted from the interactive sign-in path in [AuthController] (a session
/// *restore* must not count as a new account), and the action/lifecycle events
/// (scan, tutor, practice, paywall, purchase, profile, sync) are emitted by
/// their own controllers via [analyticsServiceProvider].

abstract class _$AnalyticsController extends $Notifier<void> {
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
