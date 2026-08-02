import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/identity_service.dart';
import '../../../core/security/installation_identity.dart';
import '../../subscription/application/server_usage_controller.dart';
import '../domain/app_user.dart';
import 'auth_controller.dart';
import 'auth_repository.dart';
import 'auth_service.dart' show firebaseReadyProvider;

part 'identity_controller.g.dart';

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
@Riverpod(keepAlive: true)
class IdentityController extends _$IdentityController {
  /// The account the last announcement was made for, so a rebuild or a
  /// busy/failure churn on the auth state doesn't re-announce needlessly.
  String? _announcedFor;

  /// Serialises announcements. A sign-in can land while the launch sequence is
  /// still in flight, and the two must not race to register the same
  /// installation — nor may the second be dropped in favour of the first, since
  /// it is the one carrying the new uid. So they queue.
  Future<void>? _queue;

  @override
  void build() {
    // Re-announce whenever the ACCOUNT identity changes. `currentUserProvider`
    // is null both for signed-out and for an anonymous session (anonymous users
    // deliberately don't surface as an `AppUser`), so this fires on the
    // transitions that matter and not on cosmetic auth-state churn.
    ref.listen<AppUser?>(currentUserProvider, (previous, next) {
      if (previous?.id == next?.id) return;
      if (next == null) {
        // Signed out: the next account must not inherit this one's meter.
        ref.read(serverUsageControllerProvider.notifier).clear();
        _announcedFor = null;
        return;
      }
      unawaited(announce());
    });

    unawaited(_bootstrap());
  }

  /// Resolves the installation id and the initial (possibly anonymous) session,
  /// then announces. Runs once per launch.
  Future<void> _bootstrap() async {
    if (!ref.read(firebaseReadyProvider)) return;
    await InstallationIdentity.initialize();
    // Layer 2. Does nothing when a real session was restored from disk.
    await ref.read(authRepositoryProvider).ensureAnonymousSession();
    await announce();
  }

  /// Registers this installation under the current account and refreshes the
  /// meter. Safe to call repeatedly — a repeat for an account already announced
  /// costs nothing, and overlapping calls run in order rather than at once.
  Future<void> announce() {
    // `catchError` keeps the queue alive: one failed announcement must not
    // poison every later one. Failures are already logged where they happen.
    final next = (_queue ?? Future<void>.value())
        .then((_) => _announce())
        .catchError((_) {});
    _queue = next;
    return next;
  }

  Future<void> _announce() async {
    if (!ref.read(firebaseReadyProvider)) return;
    final uid = ref.read(currentUserProvider)?.id;
    if (uid != null && uid == _announcedFor) return;

    await ref.read(identityServiceProvider).registerInstallation();
    _announcedFor = uid;

    // The meter is only meaningful for a real account — the backend isn't
    // reachable for an anonymous session (see [aiBackendReadyProvider]).
    if (uid != null) {
      await ref.read(serverUsageControllerProvider.notifier).refresh();
    }
  }

  /// Folds the anonymous session's usage into the account that just signed in,
  /// then re-announces under the new uid.
  ///
  /// Called from [AuthController] on the INTERACTIVE sign-in path only — a
  /// silent session restore has no anonymous session to absorb.
  Future<void> linkAfterSignIn(String? previousUid) async {
    if (!ref.read(firebaseReadyProvider)) return;
    await ref
        .read(identityServiceProvider)
        .linkIdentity(previousUid: previousUid);
    // Force a re-announce: the uid changed, so the device→account binding and
    // the meter both need re-reading.
    _announcedFor = null;
    await announce();
  }
}
