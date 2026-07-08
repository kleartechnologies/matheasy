import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/progress_stats.dart';

/// Persists [ProgressStats] locally — the Firestore-ready seam.
abstract interface class ProgressStatsRepository {
  ProgressStats load();
  Future<void> save(ProgressStats stats);
}

/// Local, on-device implementation (JSON in shared_preferences).
class LocalProgressStatsRepository implements ProgressStatsRepository {
  const LocalProgressStatsRepository(this._prefs);

  final PreferencesStore _prefs;

  @override
  ProgressStats load() {
    final raw = _prefs.progressStatsJson;
    if (raw == null || raw.isEmpty) return ProgressStats.empty;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return ProgressStats(
        scans: _int(map['scans']),
        tutorUses: _int(map['tutorUses']),
        learningDays: {
          for (final day in (map['learningDays'] as List? ?? []))
            if (day is int) day,
        },
        recentActivity: [
          for (final entry in (map['recentActivity'] as List? ?? []))
            ?_activityFromJson(entry),
        ],
      );
    } catch (_) {
      return ProgressStats.empty;
    }
  }

  @override
  Future<void> save(ProgressStats stats) {
    final json = {
      'scans': stats.scans,
      'tutorUses': stats.tutorUses,
      'learningDays': stats.learningDays.toList(),
      'recentActivity': [
        for (final activity in stats.recentActivity) _activityToJson(activity),
      ],
    };
    return _prefs.setProgressStatsJson(jsonEncode(json));
  }

  Map<String, dynamic> _activityToJson(LearningActivity a) => {
        'type': a.type.name,
        'title': a.title,
        'subtitle': a.subtitle,
        'epochMillis': a.epochMillis,
        'emoji': a.emoji,
      };

  LearningActivity? _activityFromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = _activityType(raw['type'] as String?);
    if (type == null) return null;
    return LearningActivity(
      type: type,
      title: raw['title'] as String? ?? '',
      subtitle: raw['subtitle'] as String? ?? '',
      epochMillis: _int(raw['epochMillis']),
      emoji: raw['emoji'] as String?,
    );
  }

  LearningActivityType? _activityType(String? name) {
    if (name == null) return null;
    for (final type in LearningActivityType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  int _int(Object? value) => value is int ? value : 0;
}

/// Provides the active [ProgressStatsRepository] (local today).
final Provider<ProgressStatsRepository> progressStatsRepositoryProvider =
    Provider<ProgressStatsRepository>(
  (ref) => LocalProgressStatsRepository(ref.watch(preferencesStoreProvider)),
);
