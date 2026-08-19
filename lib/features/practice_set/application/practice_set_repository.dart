import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/practice_set.dart';

/// Local persistence for [PracticeSet]s — one JSON blob under
/// `practice.sets`, most-recent-first, bounded. The same serialized string the
/// sync layer moves for `SyncDomain.practiceSets`, so the two can never drift.
abstract interface class PracticeSetRepository {
  List<PracticeSet> load();
  Future<void> save(List<PracticeSet> sets);
}

class LocalPracticeSetRepository implements PracticeSetRepository {
  const LocalPracticeSetRepository(this._store);

  final PreferencesStore _store;

  /// A generous bound — practice sets are small, but unbounded prefs blobs are
  /// how an app gets slow. Mirrors the sync merge's cap.
  static const int maxSets = 50;

  @override
  List<PracticeSet> load() {
    final raw = _store.practiceSetsJson;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const [];
      final entries = decoded['sets'];
      if (entries is! List) return const [];
      return [
        for (final e in entries)
          if (e is Map)
            ...?_valid(PracticeSet.tryFromJson(Map<String, dynamic>.from(e))),
      ];
    } catch (_) {
      return const []; // corrupt blob → start fresh, never crash
    }
  }

  @override
  Future<void> save(List<PracticeSet> sets) {
    final bounded = sets.length > maxSets ? sets.sublist(0, maxSets) : sets;
    return _store.setPracticeSetsJson(
      jsonEncode({
        'sets': [for (final s in bounded) s.toJson()],
      }),
    );
  }

  static List<PracticeSet>? _valid(PracticeSet? set) =>
      set == null ? null : [set];
}

final Provider<PracticeSetRepository> practiceSetRepositoryProvider =
    Provider<PracticeSetRepository>(
  (ref) => LocalPracticeSetRepository(ref.watch(preferencesStoreProvider)),
);
