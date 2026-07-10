import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/practice_history.dart';

/// Persists the anti-repetition [PracticeHistory] — the seam a cloud
/// implementation later replaces, mirroring [PracticeRepository].
///
/// The domain stays storage-agnostic; this layer owns serialization. A corrupt
/// or missing payload degrades to [PracticeHistory.empty] rather than throwing —
/// a bad history should never block practice generation.
abstract interface class PracticeHistoryStore {
  PracticeHistory load();

  Future<void> save(PracticeHistory history);
}

/// Local, on-device implementation backed by [PreferencesStore] (JSON in
/// shared_preferences).
class LocalPracticeHistoryStore implements PracticeHistoryStore {
  const LocalPracticeHistoryStore(this._prefs);

  final PreferencesStore _prefs;

  @override
  PracticeHistory load() {
    final raw = _prefs.practiceHistoryJson;
    if (raw == null || raw.isEmpty) return PracticeHistory.empty;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return PracticeHistory.empty;
      final recent = decoded['recent'];
      if (recent is! List) return PracticeHistory.empty;
      final values = [for (final e in recent) if (e is String) e];
      // Guard against a persisted list larger than the cap (schema drift).
      final trimmed = values.length <= PracticeHistory.maxEntries
          ? values
          : values.sublist(values.length - PracticeHistory.maxEntries);
      return PracticeHistory(recent: trimmed);
    } catch (_) {
      return PracticeHistory.empty;
    }
  }

  @override
  Future<void> save(PracticeHistory history) => _prefs.setPracticeHistoryJson(
        jsonEncode({'recent': history.recent}),
      );
}

/// Provides the active [PracticeHistoryStore] (local today).
final Provider<PracticeHistoryStore> practiceHistoryStoreProvider =
    Provider<PracticeHistoryStore>(
  (ref) => LocalPracticeHistoryStore(ref.watch(preferencesStoreProvider)),
);
