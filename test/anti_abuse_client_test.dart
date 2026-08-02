import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/security/installation_identity.dart';
import 'package:matheasy/features/auth/application/auth_controller.dart';
import 'package:matheasy/features/auth/application/auth_repository.dart';
import 'package:matheasy/features/subscription/application/server_usage_controller.dart';
import 'package:matheasy/features/subscription/application/usage_controller.dart';
import 'package:matheasy/features/subscription/domain/server_usage.dart';
import 'package:matheasy/features/subscription/domain/usage_counts.dart';
import 'package:matheasy/features/subscription/domain/usage_quota.dart';
import 'package:matheasy/features/subscription/domain/usage_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fake_auth_service.dart';

/// The CLIENT half of the anti-abuse system.
///
/// Everything here is presentation and bookkeeping — the enforcement tests live
/// in `functions/test/antiAbuse.test.ts`, because that is where enforcement
/// lives. What these pin down is that the client (a) always tells the server
/// which installation is calling, (b) shows the meter the server will actually
/// enforce rather than a hopeful local one, and (c) hands over the anonymous uid
/// so a sign-in absorbs its usage instead of abandoning it.
void main() {
  group('installation id on every call', () {
    tearDown(() => InstallationIdentity.debugSet(null));

    test('is stamped onto an outgoing payload', () {
      InstallationIdentity.debugSet('fid-abc');
      expect(
        withInstallationId(const {'latex': 'x+1'}),
        {'latex': 'x+1', 'installationId': 'fid-abc'},
      );
    });

    test('is omitted — never sent as null — when the device has none', () {
      InstallationIdentity.debugSet(null);
      final payload = withInstallationId(const {'latex': 'x+1'});
      expect(payload.containsKey('installationId'), isFalse);
    });

    test('never overwrites one the caller set explicitly', () {
      InstallationIdentity.debugSet('fid-abc');
      expect(
        withInstallationId(const {'installationId': 'explicit'}),
        {'installationId': 'explicit'},
      );
    });

    test('does not mutate the caller\'s map', () {
      InstallationIdentity.debugSet('fid-abc');
      final original = <String, dynamic>{'latex': 'x+1'};
      withInstallationId(original);
      expect(original.keys, ['latex']);
    });
  });

  group('ServerUsage parsing', () {
    test('reads the callable response', () {
      final usage = ServerUsage.fromJson(const {
        'isPro': false,
        'entitlement': 'none',
        'expiresAtMs': null,
        'used': {'scans': 4, 'tutorMessages': 2, 'practiceQuestions': 0},
        'limits': {'scans': 5, 'tutorMessages': 20, 'practiceQuestions': 0},
        'remaining': {'scans': 1},
      });

      expect(usage.isPro, isFalse);
      expect(usage.counts.scansUsed, 4);
      expect(usage.quota.scans, 5);
      expect(usage.quota.practiceQuestions, 0);
    });

    test('carries an unlimited (Pro) ceiling through as unlimited', () {
      final usage = ServerUsage.fromJson(const {
        'isPro': true,
        'entitlement': 'active',
        'expiresAtMs': 1780000000000,
        'used': {'scans': 900},
        'limits': {'scans': -1, 'tutorMessages': -1, 'practiceQuestions': -1},
      });

      expect(usage.isPro, isTrue);
      expect(usage.expiresAtMs, 1780000000000);
      expect(usage.quota.scans, UsageQuota.unlimited);
    });

    test('degrades a malformed payload instead of throwing', () {
      final usage = ServerUsage.fromJson(const {
        'isPro': 'yes',
        'entitlement': 42,
        'used': 'nonsense',
        'limits': {'scans': 'five'},
      });

      expect(usage.isPro, isFalse, reason: 'only a real bool means Pro');
      expect(usage.entitlement, 'none');
      expect(usage.counts, UsageCounts.empty);
      expect(usage.quota.scans, UsageQuota.free.scans,
          reason: 'an unreadable limit falls back to the compiled one');
    });

    test('a negative used-count never reads as extra allowance', () {
      final usage = ServerUsage.fromJson(const {
        'used': {'scans': -20},
      });
      expect(usage.counts.scansUsed, 0);
    });
  });

  group('UsageCounts.mergedWith', () {
    test('takes the larger of each counter, never the sum', () {
      const local = UsageCounts(scansUsed: 3, tutorMessagesUsed: 1);
      const server = UsageCounts(scansUsed: 2, tutorMessagesUsed: 7);

      final merged = local.mergedWith(server);
      expect(merged.scansUsed, 3);
      expect(merged.tutorMessagesUsed, 7);
    });

    test('is idempotent, so reconciling every launch converges', () {
      const local = UsageCounts(scansUsed: 3);
      const server = UsageCounts(scansUsed: 5);
      final once = local.mergedWith(server);
      expect(once.mergedWith(server), once);
      expect(once.mergedWith(server).mergedWith(server), once);
    });
  });

  group('the meter shows what the server will enforce', () {
    Future<UsageSnapshot> snapshotWith(ServerUsage? server) async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          if (server != null)
            serverUsageControllerProvider.overrideWith(
              () => _StubServerUsage(server),
            ),
        ],
      );
      addTearDown(container.dispose);
      return container.read(usageSnapshotProvider);
    }

    test('with no server answer yet, behaviour is exactly as before', () async {
      final snapshot = await snapshotWith(null);
      expect(snapshot.quota, UsageQuota.free);
      expect(snapshot.remainingScans, UsageQuota.free.scans);
    });

    // The whole point of the system: a wiped local ledger (fresh install, new
    // account, cleared preferences) must not read as a fresh allowance.
    test('a spent server ledger overrides an empty local one', () async {
      final snapshot = await snapshotWith(
        const ServerUsage(
          isPro: false,
          entitlement: 'none',
          counts: UsageCounts(scansUsed: 5),
          quota: UsageQuota.free,
        ),
      );

      expect(snapshot.canScan, isFalse);
      expect(snapshot.remainingScans, 0);
    });

    test('the server\'s Remote Config ceiling replaces the compiled one',
        () async {
      final snapshot = await snapshotWith(
        const ServerUsage(
          isPro: false,
          entitlement: 'none',
          counts: UsageCounts(scansUsed: 5),
          quota: UsageQuota(scans: 8, tutorMessages: 20, practiceQuestions: 0),
        ),
      );

      expect(snapshot.canScan, isTrue, reason: 'the limit was raised remotely');
      expect(snapshot.remainingScans, 3);
    });

    test('a server-side Pro entitlement uncaps the meter', () async {
      final snapshot = await snapshotWith(
        const ServerUsage(
          isPro: true,
          entitlement: 'grace',
          counts: UsageCounts(scansUsed: 900),
          quota: UsageQuota.free,
        ),
      );

      expect(snapshot.canScan, isTrue);
      expect(snapshot.remainingScans, UsageQuota.unlimited);
    });
  });

  group('anonymous session hand-off', () {
    test('a sign-in from a fresh install carries the anonymous uid over',
        () async {
      final auth = FakeAuthService()..anonymousUid = 'anon-7';
      addTearDown(auth.dispose);
      final container = await sessionContainer(authService: auth);
      addTearDown(container.dispose);

      final repository = container.read(authRepositoryProvider);
      expect(await repository.ensureAnonymousSession(), 'anon-7');
      expect(repository.lastAnonymousUid, isNull,
          reason: 'nothing has signed in yet');

      await container.read(authControllerProvider.notifier).signInWithGoogle();

      // This is what `linkIdentity` sends as `previousUid`, so the anonymous
      // session's spent usage is absorbed rather than abandoned.
      expect(repository.lastAnonymousUid, 'anon-7');
    });

    test('signing in over an existing account carries nothing', () async {
      final auth = FakeAuthService(initialUser: appleTestUser());
      addTearDown(auth.dispose);
      final container = await sessionContainer(authService: auth);
      addTearDown(container.dispose);

      final repository = container.read(authRepositoryProvider);
      await container.read(authControllerProvider.notifier).signInWithGoogle();

      expect(repository.lastAnonymousUid, isNull,
          reason: 'there was no anonymous session to merge');
    });

    test('ensureAnonymousSession is a no-op when a session already exists',
        () async {
      final auth = FakeAuthService(initialUser: googleTestUser());
      addTearDown(auth.dispose);
      final container = await sessionContainer(authService: auth);
      addTearDown(container.dispose);

      final uid =
          await container.read(authRepositoryProvider).ensureAnonymousSession();

      expect(uid, googleTestUser().id);
      expect(auth.anonymousSessionCount, 0,
          reason: 'a restored account must not spawn an anonymous one');
    });
  });
}

/// A [ServerUsageController] pinned to a fixed server answer.
class _StubServerUsage extends ServerUsageController {
  _StubServerUsage(this._usage);

  final ServerUsage _usage;

  @override
  ServerUsage? build() => _usage;
}
