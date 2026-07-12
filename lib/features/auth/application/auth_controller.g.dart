// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The single source of truth for the auth session.
///
/// Subscribes to the [AuthRepository]'s merged user stream (cloud + guest) and
/// projects it into an [AuthState]. Kept alive for the whole app so the session
/// survives navigation, and so a returning user's restored session is observed
/// exactly once on launch.

@ProviderFor(AuthController)
final authControllerProvider = AuthControllerProvider._();

/// The single source of truth for the auth session.
///
/// Subscribes to the [AuthRepository]'s merged user stream (cloud + guest) and
/// projects it into an [AuthState]. Kept alive for the whole app so the session
/// survives navigation, and so a returning user's restored session is observed
/// exactly once on launch.
final class AuthControllerProvider
    extends $NotifierProvider<AuthController, AuthState> {
  /// The single source of truth for the auth session.
  ///
  /// Subscribes to the [AuthRepository]'s merged user stream (cloud + guest) and
  /// projects it into an [AuthState]. Kept alive for the whole app so the session
  /// survives navigation, and so a returning user's restored session is observed
  /// exactly once on launch.
  AuthControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authControllerHash();

  @$internal
  @override
  AuthController create() => AuthController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthState>(value),
    );
  }
}

String _$authControllerHash() => r'a8a1e0f3a420ec7dbfc798c313351b907404d270';

/// The single source of truth for the auth session.
///
/// Subscribes to the [AuthRepository]'s merged user stream (cloud + guest) and
/// projects it into an [AuthState]. Kept alive for the whole app so the session
/// survives navigation, and so a returning user's restored session is observed
/// exactly once on launch.

abstract class _$AuthController extends $Notifier<AuthState> {
  AuthState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AuthState, AuthState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AuthState, AuthState>,
              AuthState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The coarse session gate the router reads. Guest counts as authenticated so
/// guests can browse the whole app. Only notifies when the [AuthStatus] value
/// actually changes (busy/failure churn on [AuthState] is filtered out).

@ProviderFor(authStatus)
final authStatusProvider = AuthStatusProvider._();

/// The coarse session gate the router reads. Guest counts as authenticated so
/// guests can browse the whole app. Only notifies when the [AuthStatus] value
/// actually changes (busy/failure churn on [AuthState] is filtered out).

final class AuthStatusProvider
    extends $FunctionalProvider<AuthStatus, AuthStatus, AuthStatus>
    with $Provider<AuthStatus> {
  /// The coarse session gate the router reads. Guest counts as authenticated so
  /// guests can browse the whole app. Only notifies when the [AuthStatus] value
  /// actually changes (busy/failure churn on [AuthState] is filtered out).
  AuthStatusProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authStatusProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authStatusHash();

  @$internal
  @override
  $ProviderElement<AuthStatus> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthStatus create(Ref ref) {
    return authStatus(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthStatus>(value),
    );
  }
}

String _$authStatusHash() => r'14390aa155bfe1afbc0349ea276cbdcb9f140378';

/// The current [AppUser] (real or guest), or `null` when signed out.

@ProviderFor(currentUser)
final currentUserProvider = CurrentUserProvider._();

/// The current [AppUser] (real or guest), or `null` when signed out.

final class CurrentUserProvider
    extends $FunctionalProvider<AppUser?, AppUser?, AppUser?>
    with $Provider<AppUser?> {
  /// The current [AppUser] (real or guest), or `null` when signed out.
  CurrentUserProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentUserProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentUserHash();

  @$internal
  @override
  $ProviderElement<AppUser?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppUser? create(Ref ref) {
    return currentUser(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppUser? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppUser?>(value),
    );
  }
}

String _$currentUserHash() => r'dff158becf63375a0d2eb064bf256e09b5c3166f';

/// The assembled [UserProfile] (identity + onboarding-derived preferences), or
/// `null` when signed out.

@ProviderFor(userProfile)
final userProfileProvider = UserProfileProvider._();

/// The assembled [UserProfile] (identity + onboarding-derived preferences), or
/// `null` when signed out.

final class UserProfileProvider
    extends $FunctionalProvider<UserProfile?, UserProfile?, UserProfile?>
    with $Provider<UserProfile?> {
  /// The assembled [UserProfile] (identity + onboarding-derived preferences), or
  /// `null` when signed out.
  UserProfileProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'userProfileProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$userProfileHash();

  @$internal
  @override
  $ProviderElement<UserProfile?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  UserProfile? create(Ref ref) {
    return userProfile(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UserProfile? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UserProfile?>(value),
    );
  }
}

String _$userProfileHash() => r'89081e999780368176bc3683e144db724b65c2b3';
