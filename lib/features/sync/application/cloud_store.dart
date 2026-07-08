import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_service.dart' show firebaseReadyProvider;
import '../domain/cloud_record.dart';
import '../domain/sync_domain.dart';

/// A cloud failure surfaced to the sync engine, classifying connectivity issues
/// ([isOffline] — retryable, not a real error) apart from hard failures. Keeps
/// the Firestore `FirebaseException` type quarantined in this file.
class CloudException implements Exception {
  const CloudException(this.message, {this.isOffline = false});

  final String message;
  final bool isOffline;

  @override
  String toString() => 'CloudException($message, offline: $isOffline)';
}

/// The remote data layer — reads/writes each user's per-domain documents.
///
/// This is the ONLY sync file that imports `cloud_firestore`; the SDK stays
/// quarantined behind [FirestoreCloudStore], exactly like Firebase Auth and
/// RevenueCat. Firestore is the *remote*, never the source of truth — the app's
/// local store is (offline-first).
abstract interface class CloudStore {
  /// Reads a single domain document, or `null` if it doesn't exist yet.
  Future<CloudRecord?> fetch(String uid, SyncDomain domain);

  /// Reads every domain document for the user in one round-trip.
  Future<Map<SyncDomain, CloudRecord>> fetchAll(String uid);

  /// Writes (overwrites) a single domain document.
  Future<void> put(String uid, SyncDomain domain, CloudRecord record);

  /// Deletes all of the user's synced documents (account deletion).
  Future<void> wipe(String uid);
}

/// Real Firestore implementation. Layout: `users/{uid}/state/{domain}`.
class FirestoreCloudStore implements CloudStore {
  const FirestoreCloudStore(this._db);

  final FirebaseFirestore _db;

  /// Caps every round-trip. With Firestore's own cache disabled, an offline
  /// read throws `unavailable` quickly, but an offline *write* can stall
  /// indefinitely (the SDK queues it in memory) — this timeout classifies that
  /// as retryable-offline instead of hanging the sync.
  static const Duration _timeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> _state(String uid) =>
      _db.collection('users').doc(uid).collection('state');

  @override
  Future<CloudRecord?> fetch(String uid, SyncDomain domain) => _guard(() async {
        final snap = await _state(uid).doc(domain.docId).get();
        return snap.exists ? CloudRecord.fromFirestore(snap.data()) : null;
      });

  @override
  Future<Map<SyncDomain, CloudRecord>> fetchAll(String uid) => _guard(() async {
        final snap = await _state(uid).get();
        final result = <SyncDomain, CloudRecord>{};
        for (final doc in snap.docs) {
          final domain = SyncDomain.fromDocId(doc.id);
          final record = CloudRecord.fromFirestore(doc.data());
          if (domain != null && record != null) result[domain] = record;
        }
        return result;
      });

  @override
  Future<void> put(String uid, SyncDomain domain, CloudRecord record) =>
      _guard(() => _state(uid).doc(domain.docId).set(record.toFirestore()));

  @override
  Future<void> wipe(String uid) => _guard(() async {
        final snap = await _state(uid).get();
        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      });

  /// Runs [op] with a timeout, translating Firestore errors and stalls into a
  /// typed [CloudException] so the sync engine never hangs and can classify
  /// offline vs. hard failure.
  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op().timeout(_timeout);
    } on TimeoutException {
      throw const CloudException('Sync timed out', isOffline: true);
    } on FirebaseException catch (error) {
      const offlineCodes = {'unavailable', 'deadline-exceeded', 'cancelled'};
      throw CloudException(
        error.message ?? error.code,
        isOffline: offlineCodes.contains(error.code),
      );
    }
  }
}

/// In-memory implementation for tests and the not-yet-provisioned checkout
/// (guests never sync, so this is effectively inert in the app). [offline] makes
/// every call throw a retryable [CloudException] to exercise offline handling.
class InMemoryCloudStore implements CloudStore {
  InMemoryCloudStore({this.offline = false});

  bool offline;
  final Map<String, Map<SyncDomain, CloudRecord>> _byUser = {};

  void _guard() {
    if (offline) throw const CloudException('offline', isOffline: true);
  }

  @override
  Future<CloudRecord?> fetch(String uid, SyncDomain domain) async {
    _guard();
    return _byUser[uid]?[domain];
  }

  @override
  Future<Map<SyncDomain, CloudRecord>> fetchAll(String uid) async {
    _guard();
    return {...?_byUser[uid]};
  }

  @override
  Future<void> put(String uid, SyncDomain domain, CloudRecord record) async {
    _guard();
    (_byUser[uid] ??= {})[domain] = record;
  }

  @override
  Future<void> wipe(String uid) async {
    _guard();
    _byUser.remove(uid);
  }
}

/// One-time Firestore configuration, called from `bootstrap` when Firebase is
/// ready. Disables Firestore's own offline cache: the app's local store is the
/// source of truth, so the sync engine wants explicit server round-trips (and
/// clean offline detection), not a second silent cache.
void configureFirestore() {
  FirebaseFirestore.instance.settings =
      const Settings(persistenceEnabled: false);
}

/// Provides the active [CloudStore] — real Firestore when Firebase is ready,
/// otherwise the inert in-memory store. Overridden in tests.
final Provider<CloudStore> cloudStoreProvider = Provider<CloudStore>((ref) {
  if (ref.watch(firebaseReadyProvider)) {
    return FirestoreCloudStore(FirebaseFirestore.instance);
  }
  return InMemoryCloudStore();
});
