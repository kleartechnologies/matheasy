import '../domain/sync_domain.dart';

/// Per-domain conflict resolution over the raw JSON payloads.
///
/// The baseline strategy is **newest wins** (by the record metadata the caller
/// passes as [remoteNewer]). For domains that are purely additive/monotonic —
/// achievements, usage counters, XP/mastery, analytics — a *merge* is used
/// instead so a two-device conflict never silently drops earned progress
/// (e.g. XP on one device, a badge on the other). Profile and settings, where a
/// single "current value" is correct, use plain newest-wins.
class SyncMerge {
  const SyncMerge._();

  /// Keep the analytics feed bounded (the local repo re-caps on next write).
  static const int _maxActivity = 20;

  static Map<String, dynamic> merge(
    SyncDomain domain, {
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required bool remoteNewer,
  }) {
    switch (domain) {
      case SyncDomain.profile:
      case SyncDomain.settings:
        return remoteNewer ? remote : local;
      case SyncDomain.usage:
        return _mergeUsage(local, remote);
      case SyncDomain.achievements:
        return _mergeAchievements(local, remote);
      case SyncDomain.progress:
        return _mergeProgress(local, remote, remoteNewer);
      case SyncDomain.analytics:
        return _mergeAnalytics(local, remote);
    }
  }

  // ---- Usage: monotonic counters → max of each. ----
  static Map<String, dynamic> _mergeUsage(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return {
      'scansUsed': _maxInt(a['scansUsed'], b['scansUsed']),
      'numiMessagesUsed': _maxInt(a['numiMessagesUsed'], b['numiMessagesUsed']),
      'practiceQuestionsGenerated':
          _maxInt(a['practiceQuestionsGenerated'], b['practiceQuestionsGenerated']),
    };
  }

  // ---- Achievements: union of unlocks, keeping the earliest unlock date. ----
  static Map<String, dynamic> _mergeAchievements(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final merged = <String, dynamic>{...a};
    b.forEach((id, millis) {
      final existing = merged[id];
      if (existing is! int || (millis is int && millis < existing)) {
        merged[id] = millis;
      }
    });
    return merged;
  }

  // ---- Progress: max monotonic fields; newest wins for the rest. ----
  static Map<String, dynamic> _mergeProgress(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    bool remoteNewer,
  ) {
    final newer = remoteNewer ? b : a;
    final topics = <String, dynamic>{};
    for (final source in [a['topics'], b['topics']]) {
      if (source is Map) {
        source.forEach((topic, value) {
          if (topic is! String || value is! Map) return;
          final existing = topics[topic];
          topics[topic] = {
            'masteryPoints': _maxInt(
                (existing is Map ? existing['masteryPoints'] : null),
                value['masteryPoints']),
            'answered': _maxInt(
                (existing is Map ? existing['answered'] : null),
                value['answered']),
            'correct': _maxInt(
                (existing is Map ? existing['correct'] : null),
                value['correct']),
          };
        });
      }
    }
    return {
      'totalXp': _maxInt(a['totalXp'], b['totalXp']),
      'streakBest': _maxInt(a['streakBest'], b['streakBest']),
      'sessionsCompleted': _maxInt(a['sessionsCompleted'], b['sessionsCompleted']),
      'dailyChallengesCompleted':
          _maxInt(a['dailyChallengesCompleted'], b['dailyChallengesCompleted']),
      'streakCurrent': newer['streakCurrent'] ?? _maxInt(a['streakCurrent'], b['streakCurrent']),
      'lastPracticedEpochDay':
          _maxNullableInt(a['lastPracticedEpochDay'], b['lastPracticedEpochDay']),
      'lastDailyChallengeEpochDay': _maxNullableInt(
          a['lastDailyChallengeEpochDay'], b['lastDailyChallengeEpochDay']),
      'topics': topics,
      'lastRequest': newer['lastRequest'] ?? a['lastRequest'] ?? b['lastRequest'],
    };
  }

  // ---- Analytics: max counts, union of days, merged activity feed. ----
  static Map<String, dynamic> _mergeAnalytics(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final days = <int>{
      ...(_intList(a['learningDays'])),
      ...(_intList(b['learningDays'])),
    };
    final activity = <Map<String, dynamic>>[
      ..._activityList(a['recentActivity']),
      ..._activityList(b['recentActivity']),
    ];
    // Dedupe by (epochMillis, title); keep the newest first, bounded.
    final seen = <String>{};
    activity.sort((x, y) =>
        _asInt(y['epochMillis']).compareTo(_asInt(x['epochMillis'])));
    final deduped = <Map<String, dynamic>>[];
    for (final entry in activity) {
      final key = '${entry['epochMillis']}|${entry['title']}';
      if (seen.add(key)) deduped.add(entry);
      if (deduped.length >= _maxActivity) break;
    }
    return {
      'scans': _maxInt(a['scans'], b['scans']),
      'tutorUses': _maxInt(a['tutorUses'], b['tutorUses']),
      'learningDays': days.toList()..sort(),
      'recentActivity': deduped,
    };
  }

  // ---- Helpers ----
  static int _asInt(Object? v) => v is int ? v : 0;

  static int _maxInt(Object? a, Object? b) {
    final x = _asInt(a);
    final y = _asInt(b);
    return x > y ? x : y;
  }

  static int? _maxNullableInt(Object? a, Object? b) {
    if (a is! int && b is! int) return null;
    return _maxInt(a, b);
  }

  static List<int> _intList(Object? v) =>
      v is List ? [for (final e in v) if (e is int) e] : const [];

  static List<Map<String, dynamic>> _activityList(Object? v) => v is List
      ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)]
      : const [];
}
