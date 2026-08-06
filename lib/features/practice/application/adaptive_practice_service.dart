import 'dart:async';
import 'dart:math';

import '../../../core/monitoring/logging_service.dart';
import '../domain/adaptive_recommendation.dart';
import '../domain/generation_tier.dart';
import '../domain/practice_difficulty.dart';
import '../domain/practice_history.dart';
import '../domain/practice_progress.dart';
import '../domain/practice_question.dart';
import '../domain/practice_session.dart';
import '../domain/practice_skill.dart';
import '../domain/practice_topic.dart';
import '../domain/question_fingerprint.dart';
import 'ai_practice_generator.dart';
import 'engine/adaptive_engine.dart';
import 'engine/difficulty_validator.dart';
import 'engine/generated_question.dart';
import 'engine/parameter_generator.dart';
import 'engine/rule_based_generator.dart';
import 'engine/similarity_engine.dart';
import 'engine/template_engine.dart';
import 'practice_history_store.dart';
import 'practice_question_bank.dart';
import 'practice_service.dart';

/// The Stage 15 Adaptive Practice Engine — the real [PracticeService].
///
/// Orchestrates the whole hybrid pipeline for one session:
///  1. **Plan** — [AdaptiveEngine] picks the `(skill, difficulty)` for each slot
///     (weakness-weighted for Pro; a basic ramp for free), honouring the tier
///     gates.
///  2. **Generate** — each slot is produced by the cheapest capable tier:
///     [TemplateEngine] (Tier 1), [RuleBasedGenerator] (Tier 2) or
///     [AiPracticeGenerator] (Tier 3, batched + Pro-only).
///  3. **De-duplicate** — [SimilarityEngine] rejects repeats against the
///     persisted [PracticeHistory] and within the session; template/rule slots
///     retry with fresh parameters, then persist their fingerprints.
///  4. **Fall back** — anything a tier can't produce (AI offline, unknown skill)
///     degrades to the hand-authored [PracticeQuestionBank] so a session always
///     builds. The whole flow never throws.
class AdaptivePracticeService implements PracticeService {
  AdaptivePracticeService({
    required PracticeProgress Function() readProgress,
    required bool Function() readIsPro,
    required this.history,
    this.aiGenerator,
    this.adaptiveEngine = const AdaptiveEngine(),
    this.templateEngine = const TemplateEngine(),
    this.ruleEngine = const RuleBasedGenerator(),
    this.similarity = const SimilarityEngine(),
    this.validator = const DifficultyValidator(),
    Random? random,
  })  : _readProgress = readProgress,
        _readIsPro = readIsPro,
        _random = random ?? Random();

  final PracticeProgress Function() _readProgress;
  final bool Function() _readIsPro;
  final PracticeHistoryStore history;
  final AiPracticeGenerator? aiGenerator;
  final AdaptiveEngine adaptiveEngine;
  final TemplateEngine templateEngine;
  final RuleBasedGenerator ruleEngine;
  final SimilarityEngine similarity;

  /// Rejects any candidate that doesn't fit the requested difficulty (concept
  /// above the level, or over the step budget) so it is regenerated, never kept.
  final DifficultyValidator validator;
  final Random _random;

  /// Attempts to re-generate a template/rule question before accepting a repeat.
  static const int _maxAttempts = 6;

  @override
  Future<PracticeSession> createSession(PracticeRequest request) async {
    final isPro = _readIsPro();
    final progress = _readProgress();
    // A seeded request (the daily challenge) must be REPRODUCIBLE: all
    // randomness derives from the seed, so re-launching the same request
    // rebuilds the identical question set.
    final seed = request.seed;
    final rng = ParameterGenerator(seed == null ? _random : Random(seed));

    final plan = adaptiveEngine.plan(
      request: request,
      progress: progress,
      isPro: isPro,
      variation: seed,
    );

    // Batch AI generation up front (one network round-trip per skill+difficulty
    // group) so a five-question calculus set doesn't fan out into five calls.
    final aiQuestions = await _prefetchAi(plan, isPro);

    // Seeded requests skip the STORED anti-repeat history: it grows with every
    // other session, so consulting it would make today's "deterministic"
    // challenge depend on what else was practiced since — a different set on
    // every relaunch. Session-internal dedupe below still applies.
    final storedHistory = seed == null ? history.load() : PracticeHistory.empty;
    final sessionValues = <String>{};
    final sessionAnswers = <String>{};
    final accepted = <QuestionFingerprint>[];
    final questions = <PracticeQuestion>[];

    for (var i = 0; i < plan.length; i++) {
      final rec = plan[i];
      final slotId = 'q$i-${rec.skill.id}';
      final generated = _generateSlot(
        rec,
        i,
        plan.length,
        rng,
        storedHistory,
        sessionValues,
        sessionAnswers,
        aiQuestions,
      );
      if (generated == null) continue;

      questions.add(generated.question.withId(slotId));
      sessionValues.add(generated.fingerprint.value);
      sessionAnswers.add(generated.fingerprint.answerSignature);
      accepted.add(generated.fingerprint);
    }

    // Ultimate safety net: if nothing generated (e.g. an all-AI plan while
    // offline and no bank content), fall back to the hand-authored bank so the
    // session is never empty.
    if (questions.isEmpty) {
      return PracticeSession(
        request: request,
        questions: _bankFallback(request),
      );
    }

    // Remember what we served so future sessions avoid repeats (fire-and-forget;
    // a persistence failure must not block practice). The seeded path bypassed
    // the stored history above, so re-load it here — saving over
    // `PracticeHistory.empty` would wipe everything already remembered.
    final base = seed == null ? storedHistory : history.load();
    unawaited(history.save(base.withAll(accepted)));

    return PracticeSession(request: request, questions: questions);
  }

  @override
  Future<PracticeQuestion?> generateOne({
    required PracticeTopic topic,
    required PracticeDifficulty difficulty,
    String? skillId,
  }) async {
    final isPro = _readIsPro();
    final clamped =
        adaptiveEngine.difficulty.clampToTier(difficulty, isPro: isPro);

    // Resolve the skill: the requested one when it fits the level, else the
    // hardest concept in the topic allowed there. No skill at all → bank.
    final requested = PracticeSkill.byId(skillId);
    var skill = (requested != null &&
            requested.topic == topic &&
            skillAllowedAt(requested, clamped) &&
            (isPro || !requested.proOnly))
        ? requested
        : null;
    if (skill == null) {
      final candidates = PracticeSkill.forTopic(topic)
          .where((s) =>
              skillAllowedAt(s, clamped) &&
              (isPro || !s.proOnly) &&
              (isPro || s.tier != GenerationTier.ai))
          .toList()
        ..sort((a, b) => conceptFloor(b).index.compareTo(conceptFloor(a).index));
      skill = candidates.isEmpty ? null : candidates.first;
    }

    // No generatable skill in this topic at this level → straight to the bank.
    if (skill == null) {
      final pool = PracticeQuestionBank.forTopic(topic)
          .where((q) => q.difficulty.index <= clamped.index)
          .toList()
        ..sort((a, b) => b.difficulty.index.compareTo(a.difficulty.index));
      return pool.isEmpty
          ? null
          : pool.first.withId('extra-${_random.nextInt(1 << 31)}');
    }

    final rec = AdaptiveRecommendation(
      skill: skill,
      difficulty: clamped,
      reason: AdaptiveReason.mastery,
    );

    final rng = ParameterGenerator(_random);
    final storedHistory = history.load();
    final sessionValues = <String>{};
    final sessionAnswers = <String>{};
    final aiQuestions = skill.tier == GenerationTier.ai && isPro
        ? await _prefetchAi([rec], isPro)
        : const <String, List<PracticeQuestion>>{};

    final generated = _generateSlot(
      rec,
      0,
      1,
      rng,
      storedHistory,
      sessionValues,
      sessionAnswers,
      aiQuestions,
    );
    if (generated == null) return null;

    unawaited(history.save(storedHistory.withAll([generated.fingerprint])));
    return generated.question.withId('extra-${_random.nextInt(1 << 31)}');
  }

  // ---- AI prefetch ---------------------------------------------------------

  /// Fetches all AI-tier slots up front, grouped by skill+difficulty. Returns a
  /// map from `skillId:difficulty` to a mutable queue the slot loop drains.
  /// Failures degrade to an empty queue (the slot then falls back on-device).
  Future<Map<String, List<PracticeQuestion>>> _prefetchAi(
    List<AdaptiveRecommendation> plan,
    bool isPro,
  ) async {
    final generator = aiGenerator;
    if (generator == null || !isPro) return const {};

    final counts = <String, int>{};
    final specs = <String, AdaptiveRecommendation>{};
    for (final rec in plan) {
      if (rec.skill.tier != GenerationTier.ai) continue;
      final key = '${rec.skill.id}:${rec.difficulty.name}';
      counts[key] = (counts[key] ?? 0) + 1;
      specs[key] = rec;
    }
    if (counts.isEmpty) return const {};

    final result = <String, List<PracticeQuestion>>{};
    for (final entry in counts.entries) {
      final rec = specs[entry.key]!;
      try {
        result[entry.key] = await generator.generate(
          skill: rec.skill,
          difficulty: rec.difficulty,
          count: entry.value,
        );
      } catch (error) {
        LoggingService.warning(
          'AI practice generation failed for ${rec.skill.id}: $error',
        );
        result[entry.key] = <PracticeQuestion>[];
      }
    }
    return result;
  }

  // ---- Per-slot generation -------------------------------------------------

  GeneratedQuestion? _generateSlot(
    AdaptiveRecommendation rec,
    int slotIndex,
    int slots,
    ParameterGenerator rng,
    PracticeHistory storedHistory,
    Set<String> sessionValues,
    Set<String> sessionAnswers,
    Map<String, List<PracticeQuestion>> aiQuestions,
  ) {
    final id = 'gen-$slotIndex';

    // AI tier: take from the prefetched, de-duplicated batch.
    if (rec.skill.tier == GenerationTier.ai) {
      final key = '${rec.skill.id}:${rec.difficulty.name}';
      final queue = aiQuestions[key];
      while (queue != null && queue.isNotEmpty) {
        final question = queue.removeAt(0);
        // Discard any AI question that doesn't fit the requested level (the
        // server also golden-rule-verifies; this is the client's second gate).
        if (!validator.isValid(question, rec.difficulty)) continue;
        final candidate = GeneratedQuestion.content(question.withId(id));
        if (!_tooSimilar(candidate, storedHistory, sessionValues,
            sessionAnswers)) {
          return candidate;
        }
      }
      // AI unavailable / exhausted (offline, backend failure, a free learner).
      // Substitute the topic's HARDEST on-device concept at this level before
      // the bank: a generated question at the requested level beats a
      // hand-authored one from below it.
      final substitute = _onDeviceSubstitute(rec);
      if (substitute != null) {
        final generated = _generateOnDeviceSlot(
          substitute,
          slotIndex,
          slots,
          rng,
          storedHistory,
          sessionValues,
          sessionAnswers,
          id,
        );
        if (generated != null) return generated;
      }
      return _bankQuestion(rec, sessionValues, sessionAnswers, id);
    }

    return _generateOnDeviceSlot(
          rec,
          slotIndex,
          slots,
          rng,
          storedHistory,
          sessionValues,
          sessionAnswers,
          id,
        ) ??
        _bankQuestion(rec, sessionValues, sessionAnswers, id);
  }

  /// The template / rule tiers: retry with fresh parameters to dodge repeats.
  /// Returns `null` when this skill has no on-device generator or every attempt
  /// failed the level check.
  GeneratedQuestion? _generateOnDeviceSlot(
    AdaptiveRecommendation rec,
    int slotIndex,
    int slots,
    ParameterGenerator rng,
    PracticeHistory storedHistory,
    Set<String> sessionValues,
    Set<String> sessionAnswers,
    String id,
  ) {
    GeneratedQuestion? last;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final candidate = _generateOnDevice(rec, slotIndex, slots, rng, id);
      if (candidate == null) break;
      // Never keep a candidate that doesn't fit the requested level — discard
      // and regenerate (bounded). `last` only tracks VALID candidates, so the
      // caller's fallback never accepts a wrong-level question.
      if (!validator.isValid(candidate.question, rec.difficulty)) continue;
      last = candidate;
      if (!_tooSimilar(candidate, storedHistory, sessionValues,
          sessionAnswers)) {
        return candidate;
      }
    }
    // Give up de-duping (bounded) and accept the last valid attempt.
    return last;
  }

  /// The best on-device stand-in for an AI slot: the hardest concept in the same
  /// topic that is still allowed at [rec]'s level. `null` when the topic is
  /// AI-only (calculus), which is exactly when the bank is the right answer.
  AdaptiveRecommendation? _onDeviceSubstitute(AdaptiveRecommendation rec) {
    final candidates = PracticeSkill.forTopic(rec.skill.topic)
        .where((s) =>
            s.tier != GenerationTier.ai && skillAllowedAt(s, rec.difficulty))
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => conceptFloor(b).index.compareTo(conceptFloor(a).index),
    );
    return AdaptiveRecommendation(
      skill: candidates.first,
      difficulty: rec.difficulty,
      reason: rec.reason,
    );
  }

  GeneratedQuestion? _generateOnDevice(
    AdaptiveRecommendation rec,
    int slotIndex,
    int slots,
    ParameterGenerator rng,
    String id,
  ) {
    switch (rec.skill.tier) {
      case GenerationTier.template:
        return templateEngine.generate(rec.skill, rec.difficulty, rng, id);
      case GenerationTier.ruleBased:
        return ruleEngine.generate(rec.skill, rec.difficulty, rng, id);
      case GenerationTier.ai:
        return null; // handled by the AI path
    }
  }

  bool _tooSimilar(
    GeneratedQuestion candidate,
    PracticeHistory storedHistory,
    Set<String> sessionValues,
    Set<String> sessionAnswers,
  ) =>
      similarity.isTooSimilar(
        candidate.fingerprint,
        history: storedHistory,
        sessionValues: sessionValues,
        sessionAnswerSignatures: sessionAnswers,
      );

  // ---- Bank fallback -------------------------------------------------------

  /// A hand-authored bank question for [rec]'s topic, preferring the requested
  /// difficulty and skipping anything already used this session.
  GeneratedQuestion? _bankQuestion(
    AdaptiveRecommendation rec,
    Set<String> sessionValues,
    Set<String> sessionAnswers,
    String id,
  ) {
    // Never serve above the slot's (already clamped + floored) level — this is
    // the free ceiling too, so a free user can't get a Hard bank question when
    // on-device generation is exhausted.
    final pool = PracticeQuestionBank.forTopic(rec.skill.topic)
        .where((q) => q.difficulty.index <= rec.difficulty.index)
        .toList();
    if (pool.isEmpty) return null;
    final ordered = [
      ...pool.where((q) => q.difficulty == rec.difficulty),
      ...pool.where((q) => q.difficulty != rec.difficulty),
    ];
    for (final question in ordered) {
      final candidate = GeneratedQuestion.content(question.withId(id));
      if (!sessionValues.contains(candidate.fingerprint.value) &&
          !sessionAnswers.contains(candidate.fingerprint.answerSignature)) {
        return candidate;
      }
    }
    // All bank questions already used this session — reuse the first anyway so a
    // slot is never dropped for an all-bank topic.
    return GeneratedQuestion.content(ordered.first.withId(id));
  }

  /// A whole session's worth of bank questions for [request] — the last-resort
  /// path when the engine produced nothing.
  List<PracticeQuestion> _bankFallback(PracticeRequest request) {
    // Clamp the requested level to the tier ceiling so a persisted/daily-challenge
    // request carrying Hard/Expert never leaks a Pro-level bank question to a free
    // user.
    final ceiling = request.difficulty == null
        ? null
        : adaptiveEngine.difficulty
            .clampToTier(request.difficulty!, isPro: _readIsPro());
    final pool = PracticeQuestionBank.forTopic(request.topic)
        .where((q) => ceiling == null || q.difficulty.index <= ceiling.index)
        .toList();
    final filtered = ceiling == null
        ? pool
        : pool.where((q) => q.difficulty == ceiling).toList();
    final source = filtered.isEmpty ? pool : filtered;
    if (source.isEmpty) return const []; // no bank question at/below the level
    source.sort((a, b) {
      final byDifficulty = a.difficulty.index.compareTo(b.difficulty.index);
      return byDifficulty != 0 ? byDifficulty : a.id.compareTo(b.id);
    });
    final count = request.questionCount.clamp(1, source.length);
    // A seeded (daily-challenge) request rotates its starting point so the
    // all-bank fallback still varies day to day instead of always serving the
    // same first N questions.
    final seed = request.seed;
    if (seed != null && source.length > count) {
      final offset = seed % source.length;
      final rotated = [...source.sublist(offset), ...source.sublist(0, offset)];
      return rotated.take(count).toList();
    }
    return source.take(count).toList();
  }
}
