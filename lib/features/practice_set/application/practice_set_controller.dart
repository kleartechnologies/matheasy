import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../history/domain/history_entry.dart';
import '../../practice/application/practice_progress_controller.dart';
import '../../progress/application/achievement_service.dart';
import '../../progress/application/stats_controller.dart';
import '../../progress/domain/progress_stats.dart';
import '../../result/application/functions_teaching_service.dart';
import '../../result/domain/result_models.dart';
import '../domain/practice_set.dart';
import 'practice_set_repository.dart';

part 'practice_set_controller.g.dart';

/// The single mutator of the learner's practice sets — the reusable
/// easier/similar/harder(/challenge) journeys generated from each solved
/// problem (spec: practice as a continuous learning system, not a
/// solution-screen footnote).
///
/// Lifecycle: a verified solve whose teaching layer carries a practice ladder
/// creates a set once ([ensureForResult]); every later verified solve is
/// checked against pending items ([recordSolved]) — attempting a rung re-enters
/// the real solve pipeline, so completion detection IS the golden-rule gate.
/// The set stays linked to its source problem until the learner finishes it or
/// explicitly re-rolls ([requestNewSet]).
///
/// XP flows through [PracticeProgressController.awardXp] — the app's one XP
/// ledger — so set rewards and session rewards stay a single currency.
@Riverpod(keepAlive: true)
class PracticeSetController extends _$PracticeSetController {
  /// Bonus XP for finishing the whole journey (core + challenge + mixed
  /// review) — deliberately equal to the daily-challenge bonus.
  static const int masteredBonusXp = 100;

  @override
  List<PracticeSet> build() => _load();

  List<PracticeSet> _load() {
    try {
      return ref.read(practiceSetRepositoryProvider).load();
    } catch (_) {
      return const []; // never let a corrupt store break solving
    }
  }

  PracticeSet? setFor(String sourceKey) {
    for (final set in state) {
      if (set.sourceKey == sourceKey) return set;
    }
    return null;
  }

  PracticeSet? setForLatex(String latex) => setFor(historyCacheKey(latex));

  /// Creates the set for a verified solve carrying a practice ladder — called
  /// when the teaching layer lands. Idempotent: an existing set for the same
  /// problem is kept untouched (the questions stay linked until completed or
  /// re-rolled), and re-solves of the SOURCE problem never reset progress.
  void ensureForResult(ResultData result) {
    final ladder = result.teaching?.practiceLadder;
    if (ladder == null || !result.verified) return;
    final key = historyCacheKey(result.equation.latex);
    if (setFor(key) != null) return;
    final set = PracticeSet.fromLadder(
      sourceKey: key,
      sourceLatex: result.equation.latex,
      sourceType: result.type,
      ladder: ladder,
      nowMillis: _now().millisecondsSinceEpoch,
    );
    _persist([set, ...state]);
  }

  /// Marks any pending set item matching the just-solved [latex] complete and
  /// pays its XP. Called on every verified solve (fresh or cache-hit) — a
  /// practice attempt goes through the full solve pipeline, so arriving here
  /// verified is exactly the completion proof the golden rule wants.
  void recordSolved(String latex) {
    if (state.isEmpty) return;
    final itemKey = historyCacheKey(latex);
    final now = _now().millisecondsSinceEpoch;
    var earnedXp = 0;
    var changed = false;

    final updated = <PracticeSet>[];
    for (final set in state) {
      if (!set.hasPendingItemKey(itemKey, historyCacheKey)) {
        updated.add(set);
        continue;
      }
      var next = set.copyWith(
        items: [
          for (final item in set.items)
            if (!item.completed && historyCacheKey(item.latex) == itemKey)
              item.complete(now)
            else
              item,
        ],
      );
      // The challenge completes on a matching solve even if the learner got to
      // it on their own before the UI unlocked it — the lock is presentation.
      final challenge = next.challenge;
      if (challenge != null &&
          !challenge.completed &&
          historyCacheKey(challenge.latex) == itemKey) {
        next = next.copyWith(challenge: challenge.complete(now));
      }
      // Pay each newly completed item's rung XP.
      for (var i = 0; i < set.allItems.length; i++) {
        final before = set.allItems[i];
        final after = next.allItems[i];
        if (!before.completed && after.completed) earnedXp += after.rung.xp;
      }
      if (next.completedCount > set.completedCount) {
        next = _maybeMaster(next, now);
        changed = true;
        updated.add(next);
      } else {
        updated.add(set);
      }
    }
    if (!changed) return;
    _persist(updated);
    if (earnedXp > 0) {
      ref.read(practiceProgressControllerProvider.notifier).awardXp(earnedXp);
    }
  }

  /// Marks the unlocked mixed-review session done for [sourceKey] (called when
  /// a practice session launched from this set completes).
  void markMixedReviewCompleted(String sourceKey) {
    final set = setFor(sourceKey);
    if (set == null || set.mixedReviewComplete) return;
    final now = _now().millisecondsSinceEpoch;
    final next = _maybeMaster(set.copyWith(mixedReviewAtMillis: now), now);
    _persist([
      for (final s in state)
        if (s.sourceKey == sourceKey) next else s,
    ]);
  }

  /// Replaces [sourceKey]'s set with a freshly-rolled one (server-verified,
  /// next variant). Returns false when no new set could be fetched — offline,
  /// free tier, or no generator for the problem type — leaving the old set.
  Future<bool> requestNewSet(String sourceKey) async {
    final existing = setFor(sourceKey);
    if (existing == null) return false;
    try {
      final ladder = await ref.read(teachingServiceProvider).fetchLadder(
            existing.sourceLatex,
            variant: existing.variant + 1,
          );
      if (ladder == null) return false;
      final fresh = PracticeSet.fromLadder(
        sourceKey: existing.sourceKey,
        sourceLatex: existing.sourceLatex,
        sourceType: existing.sourceType,
        ladder: ladder,
        nowMillis: _now().millisecondsSinceEpoch,
        variant: existing.variant + 1,
      );
      _persist([
        fresh,
        for (final s in state)
          if (s.sourceKey != sourceKey) s,
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Removes the set linked to a deleted history entry.
  void removeFor(String sourceKey) {
    if (setFor(sourceKey) == null) return;
    _persist([
      for (final s in state)
        if (s.sourceKey != sourceKey) s,
    ]);
  }

  void clear() => _persist(const []);

  /// Crowns a finished journey: mastered state, bonus XP, and a milestone in
  /// the activity feed. Runs at most once per set.
  PracticeSet _maybeMaster(PracticeSet set, int nowMillis) {
    if (set.mastered || !set.journeyComplete) return set;
    ref
        .read(practiceProgressControllerProvider.notifier)
        .awardXp(masteredBonusXp);
    ref.read(statsControllerProvider.notifier).logActivity(
          LearningActivity(
            type: LearningActivityType.milestone,
            title: 'Topic mastered',
            subtitle:
                'Completed the full practice journey for ${set.sourceType.label}',
            epochMillis: nowMillis,
          ),
        );
    return set.copyWith(masteredAtMillis: nowMillis);
  }

  DateTime _now() => ref.read(clockProvider)();

  void _persist(List<PracticeSet> sets) {
    final bounded = sets.length > LocalPracticeSetRepository.maxSets
        ? sets.sublist(0, LocalPracticeSetRepository.maxSets)
        : sets;
    state = bounded;
    unawaited(() async {
      try {
        await ref.read(practiceSetRepositoryProvider).save(bounded);
      } catch (_) {
        // Best-effort persistence — the in-memory state stays authoritative.
      }
    }());
  }
}

/// The set linked to one solved problem, by canonical key. Widgets watch this
/// so a completion anywhere re-renders every surface showing the set.
@riverpod
PracticeSet? practiceSetFor(Ref ref, String sourceKey) {
  for (final set in ref.watch(practiceSetControllerProvider)) {
    if (set.sourceKey == sourceKey) return set;
  }
  return null;
}

/// The most recent set with anything left to do — the Practice tab's
/// "continue from your last solved problem" entry point. Null when every set
/// is finished (or none exists).
@riverpod
PracticeSet? continuePracticeSet(Ref ref) {
  for (final set in ref.watch(practiceSetControllerProvider)) {
    final pendingMixedReview = set.coreComplete && !set.mixedReviewComplete;
    if (set.nextItem != null || pendingMixedReview) return set;
  }
  return null;
}
