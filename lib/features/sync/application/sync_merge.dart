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

  /// Keep the solved-problem history bounded (mirrors the local repo's cap).
  static const int _maxHistory = 200;

  /// Keep practice sets bounded (mirrors `LocalPracticeSetRepository.maxSets`).
  static const int _maxPracticeSets = 50;

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
      case SyncDomain.history:
        return _mergeHistory(local, remote);
      case SyncDomain.practiceSets:
        return _mergePracticeSets(local, remote);
    }
  }

  // ---- Usage: monotonic counters → max of each. ----
  static Map<String, dynamic> _mergeUsage(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    return {
      'scansUsed': _maxInt(a['scansUsed'], b['scansUsed']),
      'tutorMessagesUsed': _maxInt(a['tutorMessagesUsed'], b['tutorMessagesUsed']),
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

  // ---- History: union by canonical key; same key → newest by timestamp. ----
  //
  // Union means a local-only offline solve (present here, absent in the cloud)
  // survives and syncs up, and a cloud-only entry appears locally. When the same
  // problem was solved on both devices, last-write-wins by timestamp. Bounded,
  // most-recent-first — the local repo re-caps on its next write.
  static Map<String, dynamic> _mergeHistory(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final entry in [
      ..._entryList(a['entries']),
      ..._entryList(b['entries']),
    ]) {
      final key = entry['canonicalKey'];
      if (key is! String) continue;
      final existing = byKey[key];
      if (existing == null ||
          _asInt(entry['timestampMillis']) >
              _asInt(existing['timestampMillis'])) {
        byKey[key] = entry;
      }
    }
    final merged = byKey.values.toList()
      ..sort((x, y) => _asInt(y['timestampMillis'])
          .compareTo(_asInt(x['timestampMillis'])));
    return {
      'entries':
          merged.length > _maxHistory ? merged.sublist(0, _maxHistory) : merged,
    };
  }

  static List<Map<String, dynamic>> _entryList(Object? v) => v is List
      ? [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)]
      : const [];

  // ---- Practice sets: union by source problem; same problem → merge progress. ----
  //
  // Progress is additive/monotonic (a completion can't be un-earned by another
  // device), so the SAME roll of a set OR-merges item completions keeping the
  // earliest timestamps. Different rolls of the same problem ("new set" on one
  // device) can't be item-merged — the freshest roll wins whole. Bounded,
  // most-recent-first — the local repo re-caps on its next write.
  static Map<String, dynamic> _mergePracticeSets(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    for (final set in [..._entryList(a['sets']), ..._entryList(b['sets'])]) {
      final key = set['sourceKey'];
      if (key is! String) continue;
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = set;
      } else if (_asInt(existing['variant']) != _asInt(set['variant'])) {
        // Different rolls — keep the newer one whole.
        if (_asInt(set['createdAtMillis']) >
            _asInt(existing['createdAtMillis'])) {
          byKey[key] = set;
        }
      } else {
        byKey[key] = _mergeOneSet(existing, set);
      }
    }
    final merged = byKey.values.toList()
      ..sort((x, y) =>
          _asInt(y['createdAtMillis']).compareTo(_asInt(x['createdAtMillis'])));
    return {
      'sets': merged.length > _maxPracticeSets
          ? merged.sublist(0, _maxPracticeSets)
          : merged,
    };
  }

  /// OR-merges completion across the same roll of one set (earliest wins where
  /// both sides completed the same thing).
  static Map<String, dynamic> _mergeOneSet(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final itemsA = _entryList(a['items']);
    final itemsB = _entryList(b['items']);
    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < itemsA.length; i++) {
      final other = i < itemsB.length ? itemsB[i] : null;
      items.add(_mergeItem(itemsA[i], other));
    }
    final challenge = a['challenge'] is Map
        ? _mergeItem(
            Map<String, dynamic>.from(a['challenge'] as Map),
            b['challenge'] is Map
                ? Map<String, dynamic>.from(b['challenge'] as Map)
                : null,
          )
        : null;
    return {
      ...a,
      'items': items,
      'challenge': ?challenge,
      ..._earliestMillis(a, b, 'mixedReviewAtMillis'),
      ..._earliestMillis(a, b, 'masteredAtMillis'),
    };
  }

  static Map<String, dynamic> _mergeItem(
    Map<String, dynamic> a,
    Map<String, dynamic>? b,
  ) =>
      b == null ? a : {...a, ..._earliestMillis(a, b, 'completedAtMillis')};

  /// `{key: earliest-of-both}` when either side has [key], else `{}`.
  static Map<String, dynamic> _earliestMillis(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    String key,
  ) {
    final x = a[key], y = b[key];
    if (x is int && y is int) return {key: x < y ? x : y};
    if (x is int) return {key: x};
    if (y is int) return {key: y};
    return const {};
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
