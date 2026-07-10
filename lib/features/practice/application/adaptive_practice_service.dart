import 'dart:async';
import 'dart:math';

import '../../../core/monitoring/logging_service.dart';
import '../domain/adaptive_recommendation.dart';
import '../domain/generation_tier.dart';
import '../domain/practice_history.dart';
import '../domain/practice_progress.dart';
import '../domain/practice_question.dart';
import '../domain/practice_session.dart';
import '../domain/question_fingerprint.dart';
import 'ai_practice_generator.dart';
import 'engine/adaptive_engine.dart';
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
  final Random _random;

  /// Attempts to re-generate a template/rule question before accepting a repeat.
  static const int _maxAttempts = 6;

  @override
  Future<PracticeSession> createSession(PracticeRequest request) async {
    final isPro = _readIsPro();
    final progress = _readProgress();
    final rng = ParameterGenerator(_random);

    final plan = adaptiveEngine.plan(
      request: request,
      progress: progress,
      isPro: isPro,
    );

    // Batch AI generation up front (one network round-trip per skill+difficulty
    // group) so a five-question calculus set doesn't fan out into five calls.
    final aiQuestions = await _prefetchAi(plan, isPro);

    final storedHistory = history.load();
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
    // a persistence failure must not block practice).
    unawaited(history.save(storedHistory.withAll(accepted)));

    return PracticeSession(request: request, questions: questions);
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
        final candidate = GeneratedQuestion.content(question.withId(id));
        if (!_tooSimilar(candidate, storedHistory, sessionValues,
            sessionAnswers)) {
          return candidate;
        }
      }
      // AI unavailable / exhausted → hand-authored bank for this topic.
      return _bankQuestion(rec, sessionValues, sessionAnswers, id);
    }

    // Template / rule tiers: retry with fresh parameters to dodge repeats.
    GeneratedQuestion? last;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final candidate = _generateOnDevice(rec, slotIndex, slots, rng, id);
      if (candidate == null) break;
      last = candidate;
      if (!_tooSimilar(candidate, storedHistory, sessionValues,
          sessionAnswers)) {
        return candidate;
      }
    }
    // Give up de-duping (bounded) and accept the last attempt, or fall back.
    return last ?? _bankQuestion(rec, sessionValues, sessionAnswers, id);
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
    final pool = PracticeQuestionBank.forTopic(rec.skill.topic);
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
    final pool = [...PracticeQuestionBank.forTopic(request.topic)];
    final filtered = request.difficulty == null
        ? pool
        : pool.where((q) => q.difficulty == request.difficulty).toList();
    final source = filtered.isEmpty ? pool : filtered;
    source.sort((a, b) {
      final byDifficulty = a.difficulty.index.compareTo(b.difficulty.index);
      return byDifficulty != 0 ? byDifficulty : a.id.compareTo(b.id);
    });
    final count = request.questionCount.clamp(1, source.length);
    return source.take(count).toList();
  }
}
