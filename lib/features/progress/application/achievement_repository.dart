import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/achievement.dart';

/// Persists which achievements are unlocked and when — the seam a cloud
/// (Firestore) implementation later replaces with no controller/UI change.
abstract interface class AchievementRepository {
  /// Unlock dates keyed by achievement id ({} if none/corrupt).
  Map<AchievementId, DateTime> load();

  Future<void> save(Map<AchievementId, DateTime> unlocks);
}

/// Local, on-device implementation (JSON in shared_preferences).
class LocalAchievementRepository implements AchievementRepository {
  const LocalAchievementRepository(this._prefs);

  final PreferencesStore _prefs;

  @override
  Map<AchievementId, DateTime> load() {
    final raw = _prefs.achievementsJson;
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final result = <AchievementId, DateTime>{};
      map.forEach((key, value) {
        final id = _idByName(key);
        if (id != null && value is int) {
          result[id] = DateTime.fromMillisecondsSinceEpoch(value);
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<AchievementId, DateTime> unlocks) {
    final json = {
      for (final entry in unlocks.entries)
        entry.key.name: entry.value.millisecondsSinceEpoch,
    };
    return _prefs.setAchievementsJson(jsonEncode(json));
  }

  AchievementId? _idByName(String name) {
    for (final id in AchievementId.values) {
      if (id.name == name) return id;
    }
    return null;
  }
}

/// Provides the active [AchievementRepository] (local today).
final Provider<AchievementRepository> achievementRepositoryProvider =
    Provider<AchievementRepository>(
  (ref) => LocalAchievementRepository(ref.watch(preferencesStoreProvider)),
);
