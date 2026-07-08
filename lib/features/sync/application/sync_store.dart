import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/sync_domain.dart';
import '../domain/sync_metadata.dart';

/// The local side of the sync engine — a thin, typed view over
/// [PreferencesStore] keyed by [SyncDomain].
///
/// Crucially it reads/writes each domain's **already-serialized** JSON (the same
/// string the domain's local repository stores), so the sync layer needs no
/// per-model codecs and can never drift from the repositories' serialization.
class SyncStore {
  const SyncStore(this._prefs);

  final PreferencesStore _prefs;

  /// The raw JSON string for [domain], or `null` when the user has no data for
  /// it yet.
  String? readRaw(SyncDomain domain) => switch (domain) {
        SyncDomain.profile => _prefs.profileJson,
        SyncDomain.settings => _prefs.settingsJson,
        SyncDomain.progress => _prefs.practiceProgressJson,
        SyncDomain.achievements => _prefs.achievementsJson,
        SyncDomain.usage => _prefs.usageCountsJson,
        SyncDomain.analytics => _prefs.progressStatsJson,
      };

  /// The decoded payload for [domain], or `null` when absent/corrupt.
  Map<String, dynamic>? readPayload(SyncDomain domain) {
    final raw = readRaw(domain);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Overwrites [domain]'s local JSON with [payload] (a downloaded cloud copy).
  /// The owning repository re-parses this on its next `load()`.
  Future<void> writePayload(SyncDomain domain, Map<String, dynamic> payload) {
    final raw = jsonEncode(payload);
    return switch (domain) {
      SyncDomain.profile => _prefs.setProfileJson(raw),
      SyncDomain.settings => _prefs.setSettingsJson(raw),
      SyncDomain.progress => _prefs.setPracticeProgressJson(raw),
      SyncDomain.achievements => _prefs.setAchievementsJson(raw),
      SyncDomain.usage => _prefs.setUsageCountsJson(raw),
      SyncDomain.analytics => _prefs.setProgressStatsJson(raw),
    };
  }

  // ---- Conflict-resolution metadata ----

  SyncMetadata readMetadata() {
    final raw = _prefs.syncMetadataJson;
    if (raw == null || raw.isEmpty) return SyncMetadata.empty;
    try {
      return SyncMetadata.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return SyncMetadata.empty;
    }
  }

  Future<void> writeMetadata(SyncMetadata metadata) =>
      _prefs.setSyncMetadataJson(jsonEncode(metadata.toJson()));

  DateTime? get lastSyncedAt {
    final millis = _prefs.lastSyncedMillis;
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<void> setLastSyncedAt(DateTime time) =>
      _prefs.setLastSyncedMillis(time.millisecondsSinceEpoch);
}

/// Provides the [SyncStore] over the local key-value store.
final Provider<SyncStore> syncStoreProvider = Provider<SyncStore>(
  (ref) => SyncStore(ref.watch(preferencesStoreProvider)),
);
