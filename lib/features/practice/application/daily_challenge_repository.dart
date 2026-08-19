import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/daily_challenge.dart';
import '../domain/practice_topic.dart';

/// Persists [DailyChallengeState] — mirrors [PracticeRepository]'s pattern.
///
/// The domain stays storage-agnostic; this layer owns serialization. A corrupt
/// or missing payload degrades to [DailyChallengeState.empty] rather than
/// throwing — the controller then simply plans a fresh challenge.
abstract interface class DailyChallengeRepository {
  DailyChallengeState load();

  Future<void> save(DailyChallengeState state);
}

/// Local, on-device implementation backed by [PreferencesStore] (JSON in
/// shared_preferences). The same JSON blob is what the sync layer mirrors to
/// `users/{uid}/state/dailyChallenge`.
class LocalDailyChallengeRepository implements DailyChallengeRepository {
  const LocalDailyChallengeRepository(this._prefs);

  final PreferencesStore _prefs;

  @override
  DailyChallengeState load() {
    final raw = _prefs.dailyChallengeJson;
    if (raw == null || raw.isEmpty) return DailyChallengeState.empty;
    try {
      return _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return DailyChallengeState.empty;
    }
  }

  @override
  Future<void> save(DailyChallengeState state) =>
      _prefs.setDailyChallengeJson(jsonEncode(_toJson(state)));

  // ---- Serialization ----

  Map<String, dynamic> _toJson(DailyChallengeState s) => {
        'salt': s.salt,
        'dayKey': s.dayKey,
        'topic': s.topic?.name,
        'seed': s.seed,
        'questionCount': s.questionCount,
        'status': s.status.name,
        'answered': s.answered,
        'correct': s.correct,
        'completedAtMs': s.completedAtMs,
        'recent': [
          for (final r in s.recent)
            {
              'dayKey': r.dayKey,
              'topic': r.topicName,
              'status': r.statusName,
            },
        ],
      };

  DailyChallengeState _fromJson(Map<String, dynamic> m) {
    final recent = <DailyChallengeRecord>[];
    final rawRecent = m['recent'];
    if (rawRecent is List) {
      for (final entry in rawRecent) {
        if (entry is! Map) continue;
        final dayKey = entry['dayKey'];
        final topic = entry['topic'];
        if (dayKey is! int || topic is! String) continue;
        recent.add(DailyChallengeRecord(
          dayKey: dayKey,
          topicName: topic,
          statusName: entry['status'] is String ? entry['status'] as String : '',
        ));
      }
    }
    return DailyChallengeState(
      salt: _int(m['salt']),
      dayKey: m['dayKey'] is int ? m['dayKey'] as int : null,
      topic: _topicByName(m['topic'] as String?),
      seed: _int(m['seed']),
      questionCount: _int(
        m['questionCount'],
        fallback: DailyChallengeState.defaultQuestionCount,
      ),
      status: DailyChallengeStatus.fromName(m['status'] as String?),
      answered: _int(m['answered']),
      correct: _int(m['correct']),
      completedAtMs: m['completedAtMs'] is int ? m['completedAtMs'] as int : null,
      recent: recent.length <= DailyChallengeState.maxRecent
          ? recent
          : recent.sublist(0, DailyChallengeState.maxRecent),
    );
  }

  int _int(Object? value, {int fallback = 0}) =>
      value is int ? value : fallback;

  PracticeTopic? _topicByName(String? name) {
    if (name == null) return null;
    for (final topic in PracticeTopic.values) {
      if (topic.name == name) return topic;
    }
    return null;
  }
}

/// Provides the active [DailyChallengeRepository] (local today).
final Provider<DailyChallengeRepository> dailyChallengeRepositoryProvider =
    Provider<DailyChallengeRepository>(
  (ref) => LocalDailyChallengeRepository(ref.watch(preferencesStoreProvider)),
);
