/// The coarse state of cloud sync, surfaced in the UI.
enum SyncStatus {
  /// Cloud sync is off — the user is a guest (local-only) or signed out.
  disabled,

  /// Signed in but no sync has completed yet this session.
  notSynced,

  /// A sync is in progress.
  syncing,

  /// The last sync completed successfully.
  synced,

  /// The device is offline / Firestore is unreachable — local data is intact,
  /// sync will retry.
  offline,

  /// The last sync failed for a non-connectivity reason.
  error;

  bool get isBusy => this == SyncStatus.syncing;
  bool get isEnabled => this != SyncStatus.disabled;
}
