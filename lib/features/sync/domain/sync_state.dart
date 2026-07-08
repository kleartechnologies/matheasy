import 'sync_status.dart';

/// Immutable snapshot of cloud-sync state for the UI.
class SyncState {
  const SyncState({
    this.status = SyncStatus.disabled,
    this.lastSyncedAt,
    this.message,
  });

  /// The default state before anything is known — sync disabled (guest/signed
  /// out until the auth layer says otherwise).
  static const SyncState initial = SyncState();

  final SyncStatus status;

  /// When the last successful sync completed (persisted across launches), or
  /// `null` if never.
  final DateTime? lastSyncedAt;

  /// A user-safe detail for the [SyncStatus.error] / [SyncStatus.offline]
  /// states, or `null`.
  final String? message;

  bool get isSyncing => status == SyncStatus.syncing;
  bool get isEnabled => status.isEnabled;

  SyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncedAt,
    String? message,
    bool clearMessage = false,
  }) {
    return SyncState(
      status: status ?? this.status,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.status == status &&
      other.lastSyncedAt == lastSyncedAt &&
      other.message == message;

  @override
  int get hashCode => Object.hash(status, lastSyncedAt, message);
}
