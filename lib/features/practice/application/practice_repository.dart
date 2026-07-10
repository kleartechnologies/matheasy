import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/practice_difficulty.dart';
import '../domain/practice_progress.dart';
import '../domain/practice_session.dart';
import '../domain/practice_topic.dart';
import '../domain/skill_mastery.dart';

/// Persists [PracticeProgress] — the seam a cloud (Firestore) implementation
/// later replaces.
///
/// The domain stays storage-agnostic; this layer owns serialization. A future
/// `FirestorePracticeRepository` implements the same interface (likely adding a
/// `watch()` stream) and is swapped in via [practiceRepositoryProvider] with no
/// change to controllers or UI.
abstract interface class PracticeRepository {
  /// Reads the saved progress (or [PracticeProgress.empty] if none/corrupt).
  PracticeProgress load();

  /// Persists [progress].
  Future<void> save(PracticeProgress progress);
}

/// Local, on-device implementation backed by [PreferencesStore] (JSON in
/// shared_preferences).
class LocalPracticeRepository implements PracticeRepository {
  const LocalPracticeRepository(this._prefs);

  final PreferencesStore _prefs;

  @override
  PracticeProgress load() {
    final raw = _prefs.practiceProgressJson;
    if (raw == null || raw.isEmpty) return PracticeProgress.empty;
    try {
      return _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt / incompatible payload — start fresh rather than crash.
      return PracticeProgress.empty;
    }
  }

  @override
  Future<void> save(PracticeProgress progress) =>
      _prefs.setPracticeProgressJson(jsonEncode(_toJson(progress)));

  // ---- Serialization ----

  Map<String, dynamic> _toJson(PracticeProgress p) => {
        'totalXp': p.totalXp,
        'streakCurrent': p.streakCurrent,
        'streakBest': p.streakBest,
        'sessionsCompleted': p.sessionsCompleted,
        'dailyChallengesCompleted': p.dailyChallengesCompleted,
        'lastPracticedEpochDay': p.lastPracticedEpochDay,
        'lastDailyChallengeEpochDay': p.lastDailyChallengeEpochDay,
        'topics': {
          for (final entry in p.topics.entries)
            entry.key.name: {
              'masteryPoints': entry.value.masteryPoints,
              'answered': entry.value.answered,
              'correct': entry.value.correct,
            },
        },
        'skills': {
          for (final entry in p.skills.entries)
            entry.key: {
              'masteryPoints': entry.value.masteryPoints,
              'attempts': entry.value.attempts,
              'correct': entry.value.correct,
              'lastSeenEpochDay': entry.value.lastSeenEpochDay,
            },
        },
        'lastRequest':
            p.lastRequest == null ? null : _requestToJson(p.lastRequest!),
      };

  PracticeProgress _fromJson(Map<String, dynamic> m) {
    final topics = <PracticeTopic, TopicProgress>{};
    final rawTopics = m['topics'];
    if (rawTopics is Map) {
      rawTopics.forEach((key, value) {
        final topic = _topicByName(key as String?);
        if (topic != null && value is Map) {
          topics[topic] = TopicProgress(
            topic: topic,
            masteryPoints: _int(value['masteryPoints']),
            answered: _int(value['answered']),
            correct: _int(value['correct']),
          );
        }
      });
    }
    final skills = <String, SkillMastery>{};
    final rawSkills = m['skills'];
    if (rawSkills is Map) {
      rawSkills.forEach((key, value) {
        if (key is String && value is Map) {
          skills[key] = SkillMastery(
            skillId: key,
            masteryPoints: _int(value['masteryPoints']),
            attempts: _int(value['attempts']),
            correct: _int(value['correct']),
            lastSeenEpochDay:
                value['lastSeenEpochDay'] is int
                    ? value['lastSeenEpochDay'] as int
                    : null,
          );
        }
      });
    }
    return PracticeProgress(
      totalXp: _int(m['totalXp']),
      streakCurrent: _int(m['streakCurrent']),
      streakBest: _int(m['streakBest']),
      sessionsCompleted: _int(m['sessionsCompleted']),
      dailyChallengesCompleted: _int(m['dailyChallengesCompleted']),
      lastPracticedEpochDay: m['lastPracticedEpochDay'] is int
          ? m['lastPracticedEpochDay'] as int
          : null,
      lastDailyChallengeEpochDay: m['lastDailyChallengeEpochDay'] is int
          ? m['lastDailyChallengeEpochDay'] as int
          : null,
      topics: topics,
      skills: skills,
      lastRequest: _requestFromJson(m['lastRequest']),
    );
  }

  Map<String, dynamic> _requestToJson(PracticeRequest r) => {
        'topic': r.topic.name,
        'difficulty': r.difficulty?.name,
        'questionCount': r.questionCount,
        'isDailyChallenge': r.isDailyChallenge,
        'title': r.title,
        'skillId': r.skillId,
        'adaptive': r.adaptive,
      };

  PracticeRequest? _requestFromJson(Object? raw) {
    if (raw is! Map) return null;
    final topic = _topicByName(raw['topic'] as String?);
    if (topic == null) return null;
    return PracticeRequest(
      topic: topic,
      difficulty: _difficultyByName(raw['difficulty'] as String?),
      questionCount: _int(raw['questionCount'], fallback: 5),
      isDailyChallenge: raw['isDailyChallenge'] == true,
      title: raw['title'] as String?,
      skillId: raw['skillId'] as String?,
      adaptive: raw['adaptive'] == true,
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

  PracticeDifficulty? _difficultyByName(String? name) {
    if (name == null) return null;
    for (final difficulty in PracticeDifficulty.values) {
      if (difficulty.name == name) return difficulty;
    }
    return null;
  }
}

/// Provides the active [PracticeRepository] (local today).
final Provider<PracticeRepository> practiceRepositoryProvider =
    Provider<PracticeRepository>(
  (ref) => LocalPracticeRepository(ref.watch(preferencesStoreProvider)),
);
