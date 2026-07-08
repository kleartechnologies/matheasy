import 'sync_domain.dart';

/// The outcome of a sync run (a full `syncAll`, or a single push).
class SyncResult {
  const SyncResult({
    required this.ok,
    this.downloaded = const {},
    this.uploaded = const {},
    this.offline = false,
    this.error,
  });

  /// A successful run, reporting which domains were pulled from / pushed to the
  /// cloud (either may be empty when everything was already in agreement).
  factory SyncResult.success({
    Set<SyncDomain> downloaded = const {},
    Set<SyncDomain> uploaded = const {},
  }) =>
      SyncResult(ok: true, downloaded: downloaded, uploaded: uploaded);

  /// The device is offline / Firestore is unreachable — not a hard failure;
  /// local data is intact and sync will retry.
  factory SyncResult.offline() => const SyncResult(ok: false, offline: true);

  /// Sync was skipped because the user isn't eligible (guest / signed out).
  factory SyncResult.skipped() => const SyncResult(ok: true);

  /// A hard failure with a user-safe [message].
  factory SyncResult.failure(String message) =>
      SyncResult(ok: false, error: message);

  final bool ok;

  /// Domains whose local copy was updated from the cloud (UI should refresh).
  final Set<SyncDomain> downloaded;

  /// Domains whose cloud copy was updated from local.
  final Set<SyncDomain> uploaded;

  /// Whether the failure was due to connectivity (retryable, not an error).
  final bool offline;

  /// User-safe error detail, or `null`.
  final String? error;

  bool get changedLocal => downloaded.isNotEmpty;
}
