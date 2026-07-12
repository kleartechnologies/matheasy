import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../../result/domain/result_models.dart';
import '../domain/history_entry.dart';

/// Persists the solved-problem [HistoryEntry] list locally — the Firestore-ready
/// seam (the sync layer mirrors the same `history.solutions` JSON to the cloud).
abstract interface class HistoryRepository {
  /// The stored entries, most-recent-first.
  List<HistoryEntry> load();

  /// Inserts (or refreshes) [result]'s entry at the front, deduped by canonical
  /// key and capped, and returns the new list.
  Future<List<HistoryEntry>> record(ResultData result,
      {required int nowMillis});

  /// Removes the entry with [canonicalKey] and returns the new list.
  Future<List<HistoryEntry>> remove(String canonicalKey);

  /// Clears all history and returns the (empty) list.
  Future<List<HistoryEntry>> clear();

  /// The cached entry for [problemLatex], or `null` when not solved before.
  /// A read — never charges a scan, never calls `solve()`.
  HistoryEntry? lookup(String problemLatex);
}

/// Local, on-device implementation (JSON in shared_preferences).
class LocalHistoryRepository implements HistoryRepository {
  const LocalHistoryRepository(this._prefs);

  final PreferencesStore _prefs;

  /// The most a device retains — bounded so history never grows without limit.
  /// Mirrors `SyncMerge._maxHistory` so a merge and a local write agree.
  static const int maxEntries = 200;

  @override
  List<HistoryEntry> load() {
    final raw = _prefs.historyJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final entries = <HistoryEntry>[
        for (final e in (map['entries'] as List? ?? const []))
          if (e is Map<String, dynamic>) HistoryEntry.fromJson(e),
      ];
      return _ordered(entries);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<HistoryEntry>> record(ResultData result,
      {required int nowMillis}) {
    final key = historyCacheKey(result.questionLatex);
    final entry = HistoryEntry(
      canonicalKey: key,
      result: result,
      timestampMillis: nowMillis,
    );
    final next = [
      entry,
      for (final e in load())
        if (e.canonicalKey != key) e,
    ];
    return _persist(next);
  }

  @override
  Future<List<HistoryEntry>> remove(String canonicalKey) {
    final next = [
      for (final e in load())
        if (e.canonicalKey != canonicalKey) e,
    ];
    return _persist(next);
  }

  @override
  Future<List<HistoryEntry>> clear() => _persist(const []);

  @override
  HistoryEntry? lookup(String problemLatex) {
    final key = historyCacheKey(problemLatex);
    for (final e in load()) {
      if (e.canonicalKey == key) return e;
    }
    return null;
  }

  Future<List<HistoryEntry>> _persist(List<HistoryEntry> entries) async {
    final ordered = _ordered(entries);
    await _prefs.setHistoryJson(jsonEncode({
      'entries': [for (final e in ordered) e.toJson()],
    }));
    return ordered;
  }

  /// Most-recent-first, bounded.
  static List<HistoryEntry> _ordered(List<HistoryEntry> entries) {
    final sorted = [...entries]
      ..sort((a, b) => b.timestampMillis.compareTo(a.timestampMillis));
    return sorted.length > maxEntries ? sorted.sublist(0, maxEntries) : sorted;
  }
}

/// Provides the active [HistoryRepository] (local today).
final Provider<HistoryRepository> historyRepositoryProvider =
    Provider<HistoryRepository>(
  (ref) => LocalHistoryRepository(ref.watch(preferencesStoreProvider)),
);
