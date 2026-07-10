// Stage 12 tests — Firebase Data Layer (offline-first cloud sync).
//
// Covers the merge/conflict-resolution policy, the SyncStore (local side), the
// SyncService engine against an in-memory CloudStore (migration, download,
// conflict, offline, idempotency, wipe), and SyncController state transitions
// (guest disabled, auth migration, download refresh, manual sync).
//
// No real Firebase is touched — cloudStoreProvider is overridden with the
// in-memory store, mirroring how the unconfigured app already resolves it.

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/features/auth/application/auth_controller.dart';
import 'package:matheasy/features/auth/domain/app_user.dart';
import 'package:matheasy/features/progress/application/achievement_service.dart'
    show clockProvider;
import 'package:matheasy/features/subscription/application/usage_controller.dart';
import 'package:matheasy/features/sync/application/cloud_repositories.dart';
import 'package:matheasy/features/sync/application/cloud_store.dart';
import 'package:matheasy/features/sync/application/sync_controller.dart';
import 'package:matheasy/features/sync/application/sync_merge.dart';
import 'package:matheasy/features/sync/application/sync_service.dart';
import 'package:matheasy/features/sync/application/sync_store.dart';
import 'package:matheasy/features/sync/domain/cloud_record.dart';
import 'package:matheasy/features/sync/domain/sync_domain.dart';
import 'package:matheasy/features/sync/domain/sync_metadata.dart';
import 'package:matheasy/features/sync/domain/sync_status.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uid = 'user-123';

AppUser _authUser({String id = _uid}) => AppUser(
      id: id,
      provider: AuthProviderType.google,
      isGuest: false,
      createdAt: DateTime(2026),
      email: 'a@b.com',
    );

Future<PreferencesStore> _prefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  return PreferencesStore(await SharedPreferences.getInstance());
}

Map<SyncDomain, CloudRepository> _repos(CloudStore store) => {
      SyncDomain.profile: CloudProfileRepository(store),
      SyncDomain.settings: CloudSettingsRepository(store),
      SyncDomain.progress: CloudProgressRepository(store),
      SyncDomain.achievements: CloudAchievementRepository(store),
      SyncDomain.usage: CloudUsageRepository(store),
      SyncDomain.analytics: CloudAnalyticsRepository(store),
    };

FirestoreSyncService _service(
  SyncStore store,
  CloudStore cloud, {
  DateTime? now,
}) =>
    FirestoreSyncService(
      store: store,
      cloudStore: cloud,
      cloudRepositories: _repos(cloud),
      clock: () => now ?? DateTime(2026, 7, 8, 12),
    );

void main() {
  // ---- Merge policy / conflict resolution ----
  group('SyncMerge', () {
    test('profile & settings use newest-wins', () {
      final local = {'v': 'local'};
      final remote = {'v': 'remote'};
      expect(
        SyncMerge.merge(SyncDomain.settings,
            local: local, remote: remote, remoteNewer: true),
        remote,
      );
      expect(
        SyncMerge.merge(SyncDomain.profile,
            local: local, remote: remote, remoteNewer: false),
        local,
      );
    });

    test('usage takes the max of each counter', () {
      final merged = SyncMerge.merge(
        SyncDomain.usage,
        local: {
          'scansUsed': 5,
          'tutorMessagesUsed': 2,
          'practiceQuestionsGenerated': 10,
        },
        remote: {
          'scansUsed': 3,
          'tutorMessagesUsed': 8,
          'practiceQuestionsGenerated': 4,
        },
        remoteNewer: true,
      );
      expect(merged['scansUsed'], 5);
      expect(merged['tutorMessagesUsed'], 8);
      expect(merged['practiceQuestionsGenerated'], 10);
    });

    test('achievements union keeps the earliest unlock', () {
      final merged = SyncMerge.merge(
        SyncDomain.achievements,
        local: {'firstScan': 100, 'streak3': 500},
        remote: {'firstScan': 80, 'mastery': 300},
        remoteNewer: false,
      );
      expect(merged['firstScan'], 80); // earliest wins
      expect(merged['streak3'], 500);
      expect(merged['mastery'], 300);
      expect(merged.length, 3);
    });

    test('progress maxes monotonic fields, newest for streakCurrent', () {
      final merged = SyncMerge.merge(
        SyncDomain.progress,
        local: {
          'totalXp': 300,
          'streakBest': 7,
          'streakCurrent': 2,
          'sessionsCompleted': 10,
          'topics': {
            'algebra': {'masteryPoints': 40, 'answered': 20, 'correct': 15},
          },
        },
        remote: {
          'totalXp': 250,
          'streakBest': 5,
          'streakCurrent': 5,
          'sessionsCompleted': 12,
          'topics': {
            'algebra': {'masteryPoints': 30, 'answered': 25, 'correct': 22},
          },
        },
        remoteNewer: true, // remote is the newer edit
      );
      expect(merged['totalXp'], 300);
      expect(merged['streakBest'], 7);
      expect(merged['sessionsCompleted'], 12);
      expect(merged['streakCurrent'], 5); // from the newer (remote)
      final algebra = merged['topics']['algebra'] as Map;
      expect(algebra['masteryPoints'], 40);
      expect(algebra['answered'], 25);
      expect(algebra['correct'], 22);
    });

    test('analytics maxes counts, unions days, dedupes activity', () {
      final merged = SyncMerge.merge(
        SyncDomain.analytics,
        local: {
          'scans': 5,
          'tutorUses': 1,
          'learningDays': [1, 2, 3],
          'recentActivity': [
            {'epochMillis': 200, 'title': 'A'},
            {'epochMillis': 100, 'title': 'B'},
          ],
        },
        remote: {
          'scans': 3,
          'tutorUses': 4,
          'learningDays': [3, 4],
          'recentActivity': [
            {'epochMillis': 200, 'title': 'A'}, // duplicate
            {'epochMillis': 300, 'title': 'C'},
          ],
        },
        remoteNewer: true,
      );
      expect(merged['scans'], 5);
      expect(merged['tutorUses'], 4);
      expect(merged['learningDays'], [1, 2, 3, 4]);
      final activity = merged['recentActivity'] as List;
      expect(activity.length, 3); // A deduped
      expect((activity.first as Map)['title'], 'C'); // newest first
    });
  });

  // ---- SyncStore (local side) ----
  group('SyncStore', () {
    test('reads/writes payloads via the existing prefs keys', () async {
      final store = SyncStore(await _prefs());
      expect(store.readPayload(SyncDomain.usage), isNull);

      await store.writePayload(SyncDomain.usage, {'scansUsed': 4});
      expect(store.readPayload(SyncDomain.usage), {'scansUsed': 4});
      // Written to the same key the usage tracker uses.
      expect(jsonDecode(store.readRaw(SyncDomain.usage)!), {'scansUsed': 4});
    });

    test('round-trips metadata and last-synced time', () async {
      final store = SyncStore(await _prefs());
      expect(store.readMetadata().metaFor(SyncDomain.settings),
          RecordMeta.zero);

      final meta = SyncMetadata.empty.withMeta(
        SyncDomain.settings,
        RecordMeta(lastModified: DateTime(2026, 7, 8), version: 3),
      );
      await store.writeMetadata(meta);
      final loaded = store.readMetadata().metaFor(SyncDomain.settings);
      expect(loaded.version, 3);
      expect(loaded.lastModified, DateTime(2026, 7, 8));

      await store.setLastSyncedAt(DateTime(2026, 7, 8, 9));
      expect(store.lastSyncedAt, DateTime(2026, 7, 8, 9));
    });
  });

  // ---- SyncService engine ----
  group('SyncService.syncAll', () {
    test('migrates local-only data up to an empty cloud', () async {
      final prefs = await _prefs();
      final store = SyncStore(prefs);
      await store.writePayload(SyncDomain.usage, {'scansUsed': 5});
      final cloud = InMemoryCloudStore();

      final result = await _service(store, cloud).syncAll(_uid);

      expect(result.ok, isTrue);
      expect(result.uploaded, contains(SyncDomain.usage));
      final record = await cloud.fetch(_uid, SyncDomain.usage);
      expect(record!.payload, {'scansUsed': 5});
      expect(store.lastSyncedAt, isNotNull);
    });

    test('downloads cloud-only data to an empty local device', () async {
      final store = SyncStore(await _prefs());
      final cloud = InMemoryCloudStore();
      await cloud.put(
        _uid,
        SyncDomain.progress,
        CloudRecord(payload: {'totalXp': 420}, updatedAt: DateTime(2026, 7, 8)),
      );

      final result = await _service(store, cloud).syncAll(_uid);

      expect(result.downloaded, contains(SyncDomain.progress));
      expect(store.readPayload(SyncDomain.progress), {'totalXp': 420});
    });

    test('conflict on settings resolves newest-wins by metadata', () async {
      final prefs = await _prefs();
      final store = SyncStore(prefs);
      // Local settings edited most recently.
      await store.writePayload(SyncDomain.settings, {'theme': 'dark'});
      await store.writeMetadata(SyncMetadata.empty.withMeta(
        SyncDomain.settings,
        RecordMeta(lastModified: DateTime(2026, 7, 8, 12), version: 4),
      ));
      final cloud = InMemoryCloudStore();
      await cloud.put(
        _uid,
        SyncDomain.settings,
        CloudRecord(
          payload: {'theme': 'light'},
          updatedAt: DateTime(2026, 7, 8, 9), // older
          version: 2,
        ),
      );

      await _service(store, cloud).syncAll(_uid);

      // Local (newer) wins on both sides.
      expect(store.readPayload(SyncDomain.settings), {'theme': 'dark'});
      final record = await cloud.fetch(_uid, SyncDomain.settings);
      expect(record!.payload, {'theme': 'dark'});
    });

    test('additive merge keeps the best of both without data loss', () async {
      final store = SyncStore(await _prefs());
      await store.writePayload(SyncDomain.usage, {'scansUsed': 5});
      final cloud = InMemoryCloudStore();
      await cloud.put(
        _uid,
        SyncDomain.usage,
        CloudRecord(
          payload: {'scansUsed': 2, 'tutorMessagesUsed': 9},
          updatedAt: DateTime(2026, 7, 8, 13), // cloud newer
        ),
      );

      await _service(store, cloud).syncAll(_uid);

      final merged = store.readPayload(SyncDomain.usage)!;
      expect(merged['scansUsed'], 5); // local kept (max)
      expect(merged['tutorMessagesUsed'], 9); // cloud kept (max)
    });

    test('offline is reported without corrupting local data', () async {
      final store = SyncStore(await _prefs());
      await store.writePayload(SyncDomain.usage, {'scansUsed': 5});
      final cloud = InMemoryCloudStore(offline: true);

      final result = await _service(store, cloud).syncAll(_uid);

      expect(result.ok, isFalse);
      expect(result.offline, isTrue);
      expect(store.readPayload(SyncDomain.usage), {'scansUsed': 5});
    });

    test('is idempotent — a second sync uploads/downloads nothing', () async {
      final store = SyncStore(await _prefs());
      // A realistic full payload (the usage tracker always writes all keys).
      await store.writePayload(SyncDomain.usage, {
        'scansUsed': 5,
        'tutorMessagesUsed': 0,
        'practiceQuestionsGenerated': 0,
      });
      final cloud = InMemoryCloudStore();
      final service = _service(store, cloud);

      await service.syncAll(_uid);
      final second = await service.syncAll(_uid);

      expect(second.uploaded, isEmpty);
      expect(second.downloaded, isEmpty);
    });

    test('pushDomain uploads one domain; wipe clears the cloud', () async {
      final store = SyncStore(await _prefs());
      await store.writePayload(SyncDomain.profile, {'displayName': 'Ada'});
      final cloud = InMemoryCloudStore();
      final service = _service(store, cloud);

      await service.pushDomain(_uid, SyncDomain.profile);
      expect(await cloud.fetch(_uid, SyncDomain.profile), isNotNull);

      await service.wipe(_uid);
      expect(await cloud.fetch(_uid, SyncDomain.profile), isNull);
    });
  });

  // ---- SyncController state transitions ----
  group('SyncController', () {
    Future<ProviderContainer> container({
      required AppUser? user,
      Map<String, Object> seed = const {},
      InMemoryCloudStore? cloud,
    }) async {
      SharedPreferences.setMockInitialValues(seed);
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWithValue(user),
          cloudStoreProvider
              .overrideWithValue(cloud ?? InMemoryCloudStore()),
          clockProvider.overrideWithValue(() => DateTime(2026, 7, 8, 12)),
        ],
      );
      addTearDown(c.dispose);
      // Keep the keepAlive sync controller alive (as AppShell does in the app),
      // so a background sync isn't orphaned by disposal mid-flight.
      c.listen(syncControllerProvider, (_, _) {});
      return c;
    }

    test('is disabled for a guest', () async {
      final c = await container(user: AppUser.guest(createdAt: DateTime(2026)));
      expect(c.read(syncControllerProvider).status, SyncStatus.disabled);
    });

    test('migrates local data on launch for a signed-in user', () async {
      final cloud = InMemoryCloudStore();
      final c = await container(
        user: _authUser(),
        cloud: cloud,
        seed: {'subscription.usage': jsonEncode({'scansUsed': 4})},
      );

      c.read(syncControllerProvider); // trigger launch sync (microtask)
      await pumpEventQueue();

      expect(c.read(syncControllerProvider).status, SyncStatus.synced);
      final record = await cloud.fetch(_uid, SyncDomain.usage);
      expect(record!.payload, {'scansUsed': 4});
    });

    test('downloads cloud data and refreshes the controller', () async {
      final cloud = InMemoryCloudStore();
      await cloud.put(
        _uid,
        SyncDomain.usage,
        CloudRecord(
          payload: {'scansUsed': 7},
          updatedAt: DateTime(2026, 7, 8, 13),
        ),
      );
      final c = await container(user: _authUser(), cloud: cloud);

      c.read(syncControllerProvider);
      await pumpEventQueue();

      expect(c.read(syncControllerProvider).status, SyncStatus.synced);
      // The usage controller reflects the downloaded value after refresh.
      expect(c.read(usageControllerProvider).scansUsed, 7);
    });

    test('offline cloud leaves the controller in the offline state', () async {
      final c = await container(
        user: _authUser(),
        cloud: InMemoryCloudStore(offline: true),
        seed: {'subscription.usage': jsonEncode({'scansUsed': 1})},
      );

      c.read(syncControllerProvider);
      await pumpEventQueue();

      expect(c.read(syncControllerProvider).status, SyncStatus.offline);
    });

    test('syncNow is a no-op for guests', () async {
      final c = await container(user: AppUser.guest(createdAt: DateTime(2026)));
      final result =
          await c.read(syncControllerProvider.notifier).syncNow();
      expect(result.ok, isTrue);
      expect(result.uploaded, isEmpty);
    });
  });

  // ---- Account boundary (the critical cross-account cases) ----
  group('SyncController account transitions', () {
    // Drives currentUserProvider off a mutable StateProvider so tests can
    // simulate sign-in / sign-out / account switches.
    final userCtl = StateProvider<AppUser?>((ref) => null);

    Future<ProviderContainer> txContainer({
      required AppUser? initial,
      Map<String, Object> seed = const {},
      required InMemoryCloudStore cloud,
    }) async {
      SharedPreferences.setMockInitialValues(seed);
      final prefs = await SharedPreferences.getInstance();
      final c = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          currentUserProvider.overrideWith((ref) => ref.watch(userCtl)),
          cloudStoreProvider.overrideWithValue(cloud),
          clockProvider.overrideWithValue(() => DateTime(2026, 7, 8, 12)),
        ],
      );
      addTearDown(c.dispose);
      c.read(userCtl.notifier).state = initial;
      c.listen(syncControllerProvider, (_, _) {}); // keep alive (as AppShell)
      return c;
    }

    test('signing out of a real account wipes local data (no leak to next user)',
        () async {
      final cloud = InMemoryCloudStore();
      final c = await txContainer(
        initial: _authUser(id: 'A'),
        cloud: cloud,
        seed: {
          'subscription.usage': jsonEncode({
            'scansUsed': 5,
            'tutorMessagesUsed': 0,
            'practiceQuestionsGenerated': 0,
          }),
        },
      );
      c.read(syncControllerProvider);
      await pumpEventQueue();
      expect(c.read(usageControllerProvider).scansUsed, 5); // A's data present

      // Sign out → local data must be cleared (A's copy is safe in the cloud).
      c.read(userCtl.notifier).state = null;
      await pumpEventQueue();
      expect(c.read(usageControllerProvider).scansUsed, 0);
      expect(c.read(syncStoreProvider).readPayload(SyncDomain.usage), isNull);
      // A's cloud data is untouched by sign-out.
      expect(await cloud.fetch('A', SyncDomain.usage), isNotNull);

      // A different user signing in does not inherit A's data.
      c.read(userCtl.notifier).state = _authUser(id: 'B');
      await pumpEventQueue();
      expect(c.read(usageControllerProvider).scansUsed, 0);
    });

    test('guest customizations survive migration into a pre-existing account',
        () async {
      final cloud = InMemoryCloudStore();
      // The account already has an older profile in the cloud.
      await cloud.put(
        'A',
        SyncDomain.profile,
        CloudRecord(
          payload: {'displayName': 'Bob', 'avatar': 'ocean'},
          updatedAt: DateTime(2026, 7), // older than the guest's edit
        ),
      );
      final c = await txContainer(
        initial: AppUser.guest(createdAt: DateTime(2026)),
        cloud: cloud,
        seed: {
          'profile.editable':
              jsonEncode({'displayName': 'Alex', 'avatar': 'sunset'}),
        },
      );
      c.read(syncControllerProvider);
      await pumpEventQueue();

      // Sign into the existing account → guest's newer name/avatar win.
      c.read(userCtl.notifier).state = _authUser(id: 'A');
      await pumpEventQueue();

      final localProfile =
          c.read(syncStoreProvider).readPayload(SyncDomain.profile);
      expect(localProfile!['displayName'], 'Alex');
      final cloudProfile = await cloud.fetch('A', SyncDomain.profile);
      expect(cloudProfile!.payload['displayName'], 'Alex');
    });
  });
}
