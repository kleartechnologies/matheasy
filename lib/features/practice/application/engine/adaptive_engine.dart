import '../../domain/adaptive_recommendation.dart';
import '../../domain/practice_difficulty.dart';
import '../../domain/practice_progress.dart';
import '../../domain/practice_session.dart';
import '../../domain/practice_skill.dart';
import '../../domain/practice_topic.dart';
import '../../domain/weakness_profile.dart';
import 'difficulty_engine.dart';

/// The adaptive brain (Pro): turns a [PracticeRequest] + the learner's
/// [PracticeProgress] into a concrete plan of `(skill, difficulty)` slots.
///
/// It decides *which skills* to practice (weakness-weighted for Pro; a basic
/// rotation for free) and *how hard* (via [DifficultyEngine]), while enforcing
/// the tier gates: the free plan only ever contains basic template skills, and
/// never [PracticeDifficulty.expert].
class AdaptiveEngine {
  const AdaptiveEngine({this.difficulty = const DifficultyEngine()});

  final DifficultyEngine difficulty;

  /// Minimum attempts before a skill contributes a weakness signal.
  static const int _minAttempts = 2;

  /// A skill scoring at or below this isn't "weak" enough to prioritise.
  static const double _weakThreshold = 0.25;

  /// Ranks the learner's weaknesses from per-skill mastery. Weakest first.
  WeaknessProfile weaknessProfile(PracticeProgress progress) {
    final scores = <WeaknessScore>[];
    for (final skill in PracticeSkill.values) {
      final mastery = progress.skill(skill);
      if (mastery.attempts < _minAttempts) continue;
      // A skill the learner never gets wrong isn't a *weakness* — it's a
      // mastery-building candidate (the difficulty engine ramps it up instead).
      // Requiring a real accuracy gap also keeps the "N% accuracy" reason
      // honest (it can never read "100% accuracy" on a weakness).
      if (mastery.accuracy >= 1.0) continue;
      final accuracyGap = (1 - mastery.accuracy).clamp(0.0, 1.0);
      final masteryGap = (1 - mastery.masteryPoints / 100).clamp(0.0, 1.0);
      final score = 0.6 * accuracyGap + 0.4 * masteryGap;
      if (score <= _weakThreshold) continue;
      scores.add(
        WeaknessScore(
          skill: skill,
          score: score,
          reason: '${(mastery.accuracy * 100).round()}% accuracy',
        ),
      );
    }
    scores.sort((a, b) => b.score.compareTo(a.score));

    final topics = <PracticeTopic>[];
    for (final s in scores) {
      if (!topics.contains(s.topic)) topics.add(s.topic);
    }
    return WeaknessProfile(skills: scores, topics: topics);
  }

  /// The single best "practice this next" suggestion, or `null` for a free
  /// learner (adaptive recommendations are Pro) / when there's no signal yet.
  AdaptiveRecommendation? nextRecommendation(
    PracticeProgress progress, {
    required bool isPro,
  }) {
    if (!isPro) return null;
    final weakest = weaknessProfile(progress).weakest;
    if (weakest == null) return null;
    final target =
        difficulty.centreFor(progress.skill(weakest.skill), isPro: isPro);
    return AdaptiveRecommendation(
      skill: weakest.skill,
      difficulty: target,
      reason: AdaptiveReason.weakness,
    );
  }

  /// Builds the ordered `(skill, difficulty)` plan for a session.
  List<AdaptiveRecommendation> plan({
    required PracticeRequest request,
    required PracticeProgress progress,
    required bool isPro,
  }) {
    final count = request.questionCount.clamp(1, 20);
    final skills = _candidateSkills(request, progress, isPro);
    final reason = _reasonFor(request, progress, isPro);

    return [
      for (var i = 0; i < count; i++)
        AdaptiveRecommendation(
          skill: skills[i % skills.length],
          difficulty: _difficultyFor(request, progress, isPro, skills[i % skills.length], i, count),
          reason: reason,
        ),
    ];
  }

  // ---- Internals -----------------------------------------------------------

  List<PracticeSkill> _candidateSkills(
    PracticeRequest request,
    PracticeProgress progress,
    bool isPro,
  ) {
    // 1. Pinned skill — personalized reinforcement. Honoured only if the tier
    //    is allowed to see it.
    final pinned = PracticeSkill.byId(request.skillId);
    if (pinned != null && (isPro || pinned.isFree)) {
      return [pinned];
    }

    // 2. The topic's skills, gated by tier.
    var pool = isPro
        ? PracticeSkill.forTopic(request.topic)
        : PracticeSkill.freeForTopic(request.topic);

    // Defensive fallback: a free learner routed to an advanced topic (no free
    // skills) gets basic skills rather than nothing / a crash. (The UI gates
    // this earlier, but the engine must never fail.)
    if (pool.isEmpty) {
      pool = isPro ? PracticeSkill.forTopic(request.topic) : PracticeSkill.freeSkills;
    }
    if (pool.isEmpty) pool = PracticeSkill.freeSkills;

    // 3. Adaptive (Pro): lead with the learner's weak skills, then cover the
    //    rest of the pool for variety.
    if (isPro && request.adaptive) {
      final weak = weaknessProfile(progress)
          .skills
          .map((s) => s.skill)
          .where(pool.contains)
          .toList();
      final rest = pool.where((s) => !weak.contains(s)).toList();
      final ordered = [...weak, ...rest];
      if (ordered.isNotEmpty) return ordered;
    }

    return pool;
  }

  PracticeDifficulty _difficultyFor(
    PracticeRequest request,
    PracticeProgress progress,
    bool isPro,
    PracticeSkill skill,
    int slotIndex,
    int slots,
  ) {
    if (request.difficulty != null) {
      return difficulty.clampToTier(request.difficulty!, isPro: isPro);
    }
    return difficulty.targetFor(
      mastery: progress.skill(skill),
      isPro: isPro,
      slotIndex: slotIndex,
      slots: slots,
    );
  }

  AdaptiveReason _reasonFor(
    PracticeRequest request,
    PracticeProgress progress,
    bool isPro,
  ) {
    if (request.skillId != null) return AdaptiveReason.reinforcement;
    if (!isPro || !request.adaptive) return AdaptiveReason.chosen;
    if (weaknessProfile(progress).hasSignal) return AdaptiveReason.weakness;
    return progress.hasHistory
        ? AdaptiveReason.mastery
        : AdaptiveReason.freshStart;
  }
}
