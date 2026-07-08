import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/cloud_record.dart';
import '../domain/sync_domain.dart';
import 'cloud_store.dart';

/// The cloud-side repository for a single [SyncDomain] — the remote counterpart
/// of that domain's local repository, paired with it behind the offline-first
/// [SyncService] so controllers stay source-agnostic.
///
/// Each concrete subclass binds one domain; together they form the cloud data
/// layer (`CloudProfileRepository`, `CloudSettingsRepository`, …). They share a
/// single [CloudStore] rather than re-opening Firestore per domain.
abstract class CloudRepository {
  const CloudRepository(this._store, this.domain);

  final CloudStore _store;
  final SyncDomain domain;

  /// Reads this domain's cloud record for [uid], or `null` if none exists.
  Future<CloudRecord?> fetch(String uid) => _store.fetch(uid, domain);

  /// Writes this domain's cloud record for [uid].
  Future<void> push(String uid, CloudRecord record) =>
      _store.put(uid, domain, record);
}

class CloudProfileRepository extends CloudRepository {
  const CloudProfileRepository(CloudStore store)
      : super(store, SyncDomain.profile);
}

class CloudSettingsRepository extends CloudRepository {
  const CloudSettingsRepository(CloudStore store)
      : super(store, SyncDomain.settings);
}

class CloudProgressRepository extends CloudRepository {
  const CloudProgressRepository(CloudStore store)
      : super(store, SyncDomain.progress);
}

class CloudAchievementRepository extends CloudRepository {
  const CloudAchievementRepository(CloudStore store)
      : super(store, SyncDomain.achievements);
}

class CloudUsageRepository extends CloudRepository {
  const CloudUsageRepository(CloudStore store)
      : super(store, SyncDomain.usage);
}

class CloudAnalyticsRepository extends CloudRepository {
  const CloudAnalyticsRepository(CloudStore store)
      : super(store, SyncDomain.analytics);
}

/// Every cloud repository keyed by domain, sharing the active [CloudStore]. The
/// [SyncService] iterates this map to sync all domains uniformly.
final Provider<Map<SyncDomain, CloudRepository>> cloudRepositoriesProvider =
    Provider<Map<SyncDomain, CloudRepository>>((ref) {
  final store = ref.watch(cloudStoreProvider);
  return {
    SyncDomain.profile: CloudProfileRepository(store),
    SyncDomain.settings: CloudSettingsRepository(store),
    SyncDomain.progress: CloudProgressRepository(store),
    SyncDomain.achievements: CloudAchievementRepository(store),
    SyncDomain.usage: CloudUsageRepository(store),
    SyncDomain.analytics: CloudAnalyticsRepository(store),
  };
});
