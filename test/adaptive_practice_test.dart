// Stage 15 tests — the Adaptive Practice Engine.
//
// Covers the hybrid generation tiers (template / rule-based / AI mapping), the
// parameter + math helpers, anti-repetition (fingerprints, similarity, history
// round-trip), difficulty + adaptive planning, per-skill mastery persistence,
// free-vs-Pro gating, and the AdaptivePracticeService orchestration end to end.
// A seeded Random keeps every generated question deterministic.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/analytics/domain/analytics_event.dart';
import 'package:matheasy/features/practice/application/adaptive_practice_service.dart';
import 'package:matheasy/features/practice/application/ai_practice_generator.dart';
import 'package:matheasy/features/practice/application/engine/adaptive_engine.dart';
import 'package:matheasy/features/practice/application/engine/difficulty_engine.dart';
import 'package:matheasy/features/practice/application/engine/generated_question.dart';
import 'package:matheasy/features/practice/application/engine/parameter_generator.dart';
import 'package:matheasy/features/practice/application/engine/practice_math.dart';
import 'package:matheasy/features/practice/application/engine/rule_based_generator.dart';
import 'package:matheasy/features/practice/application/engine/similarity_engine.dart';
import 'package:matheasy/features/practice/application/engine/template_engine.dart';
import 'package:matheasy/features/practice/application/practice_history_store.dart';
import 'package:matheasy/features/practice/domain/generation_tier.dart';
import 'package:matheasy/features/practice/domain/mastery.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_history.dart';
import 'package:matheasy/features/practice/domain/practice_mistake.dart';
import 'package:matheasy/features/practice/domain/practice_progress.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_session.dart';
import 'package:matheasy/features/practice/domain/practice_skill.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/practice/domain/question_fingerprint.dart';
import 'package:matheasy/features/practice/domain/skill_mastery.dart';

// ---- Test doubles ----------------------------------------------------------

/// An in-memory history store. `save` runs synchronously (no await before the
/// assignment), so the service's fire-and-forget save is observable right after
/// `createSession` returns.
class _MemoryHistoryStore implements PracticeHistoryStore {
  PracticeHistory _history = PracticeHistory.empty;

  @override
  PracticeHistory load() => _history;

  @override
  Future<void> save(PracticeHistory history) async => _history = history;
}

/// A fake AI generator that echoes back N simple, well-formed questions.
class _FakeAiGenerator implements AiPracticeGenerator {
  int calls = 0;

  @override
  Future<List<PracticeQuestion>> generate({
    required PracticeSkill skill,
    required PracticeDifficulty difficulty,
    required int count,
  }) async {
    calls++;
    return [
      for (var i = 0; i < count; i++)
        PracticeQuestion(
          id: 'ai-$i',
          topic: skill.topic,
          difficulty: difficulty,
          type: PracticeQuestionType.input,
          prompt: 'AI question ${calls}_$i for ${skill.label}',
          explanation: 'Because.',
          skillId: skill.id,
          acceptedAnswers: ['${calls * 10 + i}'],
        ),
    ];
  }
}

AdaptivePracticeService _service({
  PracticeProgress progress = PracticeProgress.empty,
  bool isPro = false,
  PracticeHistoryStore? history,
  AiPracticeGenerator? ai,
  int seed = 7,
}) {
  return AdaptivePracticeService(
    readProgress: () => progress,
    readIsPro: () => isPro,
    history: history ?? _MemoryHistoryStore(),
    aiGenerator: ai,
    random: Random(seed),
  );
}

void main() {
  group('PracticeDifficulty (expert tier)', () {
    test('expert carries the spec XP and is Pro-only', () {
      expect(PracticeDifficulty.easy.baseXp, 10);
      expect(PracticeDifficulty.medium.baseXp, 20);
      expect(PracticeDifficulty.hard.baseXp, 40);
      expect(PracticeDifficulty.expert.baseXp, 75);
      expect(PracticeDifficulty.expert.isPro, isTrue);
      expect(PracticeDifficulty.hard.isPro, isFalse);
    });

    test('harder / easier navigate the ladder', () {
      expect(PracticeDifficulty.easy.easier, isNull);
      expect(PracticeDifficulty.easy.harder, PracticeDifficulty.medium);
      expect(PracticeDifficulty.expert.harder, isNull);
      expect(PracticeDifficulty.expert.easier, PracticeDifficulty.hard);
    });
  });

  group('PracticeSkill taxonomy', () {
    test('free skills are all basic on-device template skills', () {
      for (final skill in PracticeSkill.freeSkills) {
        expect(skill.proOnly, isFalse);
        expect(skill.tier, GenerationTier.template);
        expect(skill.isFree, isTrue);
      }
      expect(PracticeSkill.freeSkills, isNotEmpty);
    });

    test('advanced topics have no free skills (gate free users)', () {
      expect(PracticeSkill.topicHasFreeSkills(PracticeTopic.algebra), isTrue);
      expect(PracticeSkill.topicHasFreeSkills(PracticeTopic.fractions), isTrue);
      expect(
          PracticeSkill.topicHasFreeSkills(PracticeTopic.wordProblems), isTrue);
      expect(PracticeSkill.topicHasFreeSkills(PracticeTopic.geometry), isFalse);
      expect(
          PracticeSkill.topicHasFreeSkills(PracticeTopic.trigonometry), isFalse);
      expect(PracticeSkill.topicHasFreeSkills(PracticeTopic.calculus), isFalse);
      expect(
          PracticeSkill.topicHasFreeSkills(PracticeTopic.statistics), isFalse);
    });

    test('byId round-trips and unknown ids resolve to null', () {
      for (final skill in PracticeSkill.values) {
        expect(PracticeSkill.byId(skill.id), skill);
      }
      expect(PracticeSkill.byId('nope'), isNull);
      expect(PracticeSkill.byId(null), isNull);
    });

    test('calculus skills are Pro-only AI skills', () {
      expect(PracticeSkill.calculusDerivative.proOnly, isTrue);
      expect(PracticeSkill.calculusDerivative.tier, GenerationTier.ai);
    });
  });

  group('PracticeMath helpers', () {
    test('gcd / lcm', () {
      expect(PracticeMath.gcd(12, 18), 6);
      expect(PracticeMath.gcd(0, 0), 1);
      expect(PracticeMath.lcm(4, 6), 12);
    });

    test('simplifyFraction / formatFraction', () {
      expect(PracticeMath.simplifyFraction(6, 8), (3, 4));
      expect(PracticeMath.formatFraction(4, 2), '2');
      expect(PracticeMath.formatFraction(6, 8), '3/4');
      expect(PracticeMath.formatFraction(-2, 4), '-1/2');
    });

    test('isPerfectSquare', () {
      expect(PracticeMath.isPerfectSquare(25), isTrue);
      expect(PracticeMath.isPerfectSquare(26), isFalse);
    });
  });

  group('ParameterGenerator', () {
    test('between is inclusive and deterministic with a seed', () {
      final a = ParameterGenerator(Random(1));
      final b = ParameterGenerator(Random(1));
      for (var i = 0; i < 50; i++) {
        final v = a.between(2, 9);
        expect(v, inInclusiveRange(2, 9));
        expect(v, b.between(2, 9)); // same seed → same stream
      }
    });

    test('nonZeroBetween never returns zero', () {
      final rng = ParameterGenerator(Random(3));
      for (var i = 0; i < 100; i++) {
        expect(rng.nonZeroBetween(-3, 3), isNot(0));
      }
    });
  });

  group('Template engine (Tier 1)', () {
    const engine = TemplateEngine();

    test('every free skill generates a solvable question at every difficulty',
        () {
      final rng = ParameterGenerator(Random(11));
      for (final skill in PracticeSkill.freeSkills) {
        for (final difficulty in [
          PracticeDifficulty.easy,
          PracticeDifficulty.medium,
          PracticeDifficulty.hard,
        ]) {
          final generated =
              engine.generate(skill, difficulty, rng, 'id')!;
          final q = generated.question;
          expect(q.skillId, skill.id, reason: '${skill.id} tags itself');
          expect(q.correctAnswerText, isNotEmpty,
              reason: '${skill.id} has an answer');
          expect(q.evaluate(q.correctAnswerText), isTrue,
              reason: '${skill.id} accepts its own answer');
        }
      }
    });

    test('advanced Pro template skills also generate solvable questions', () {
      final rng = ParameterGenerator(Random(5));
      for (final skill in [
        PracticeSkill.linearBothSides,
        PracticeSkill.simultaneousEquations,
        PracticeSkill.quadraticFactor,
      ]) {
        final q = engine
            .generate(skill, PracticeDifficulty.hard, rng, 'id')!
            .question;
        expect(q.evaluate(q.correctAnswerText), isTrue, reason: skill.id);
      }
    });

    test('does not generate for a rule/AI skill', () {
      final rng = ParameterGenerator(Random(1));
      expect(engine.supports(PracticeSkill.triangleAngle), isFalse);
      expect(
        engine.generate(
            PracticeSkill.triangleAngle, PracticeDifficulty.easy, rng, 'id'),
        isNull,
      );
    });

    test('multiple-choice options never duplicate the correct value', () {
      // Regression: a distractor value-equal to the correct answer (e.g.
      // 2/6 + 2/6 → answer 2/3, raw distractor 4/6) would be scored wrong
      // despite being a valid form. Exactly one option must be correct and no
      // other option may share its numeric value.
      double? value(String s) {
        final t = s.trim();
        if (t.contains('/')) {
          final parts = t.split('/');
          final n = num.tryParse(parts[0].trim());
          final d = num.tryParse(parts[1].trim());
          if (n == null || d == null || d == 0) return null;
          return n / d;
        }
        return num.tryParse(t)?.toDouble();
      }

      final rng = ParameterGenerator(Random(123));
      final mcSkills = [
        PracticeSkill.fractionAddLike,
        PracticeSkill.fractionAddUnlike,
        PracticeSkill.ratioSimplify,
      ];
      for (final skill in mcSkills) {
        for (var i = 0; i < 300; i++) {
          final difficulty = PracticeDifficulty
              .values[i % 3]; // easy / medium / hard
          final q = engine.generate(skill, difficulty, rng, 'id')!.question;
          if (q.options.isEmpty) continue;
          expect(q.options.where((o) => o.isCorrect), hasLength(1),
              reason: '${skill.id} has exactly one correct option');
          final correctIndex = q.correctOptionIndex;
          final correctValue = value(q.options[correctIndex].text);
          for (var j = 0; j < q.options.length; j++) {
            if (j == correctIndex) continue;
            final other = value(q.options[j].text);
            if (correctValue != null && other != null) {
              expect((other - correctValue).abs() > 1e-9, isTrue,
                  reason: '${skill.id}: wrong option '
                      '"${q.options[j].text}" equals the correct value');
            }
          }
        }
      }
    });
  });

  group('Rule-based engine (Tier 2)', () {
    const engine = RuleBasedGenerator();

    test('every rule skill generates a solvable question', () {
      final rng = ParameterGenerator(Random(9));
      for (final skill in PracticeSkill.values
          .where((s) => s.tier == GenerationTier.ruleBased)) {
        for (final difficulty in PracticeDifficulty.values) {
          final q =
              engine.generate(skill, difficulty, rng, 'id')!.question;
          expect(q.evaluate(q.correctAnswerText), isTrue,
              reason: '${skill.id} @ ${difficulty.name}');
        }
      }
    });

    test('triangle-angle questions always sum to 180', () {
      final rng = ParameterGenerator(Random(2));
      for (var i = 0; i < 40; i++) {
        final q = engine
            .generate(PracticeSkill.triangleAngle, PracticeDifficulty.medium,
                rng, 'id')!
            .question;
        final third = int.parse(q.correctAnswerText);
        expect(third, greaterThan(0));
        expect(third, lessThan(180));
      }
    });
  });

  group('Anti-repetition', () {
    const similarity = SimilarityEngine();

    QuestionFingerprint fp(String skill, String sig, String ans) =>
        QuestionFingerprint(skillId: skill, signature: sig, answerKey: ans);

    test('exact repeats are flagged from history and within-session', () {
      final history = PracticeHistory.empty
          .withAll([fp('s', 'a', '1')]);
      final candidate = fp('s', 'a', '1');
      expect(
        similarity.isTooSimilar(candidate,
            history: history,
            sessionValues: const {},
            sessionAnswerSignatures: const {}),
        isTrue,
      );
      // Fresh candidate against session-only state.
      final fresh = fp('s', 'b', '2');
      expect(
        similarity.isTooSimilar(fresh,
            history: PracticeHistory.empty,
            sessionValues: {fresh.value},
            sessionAnswerSignatures: const {}),
        isTrue,
      );
    });

    test('same skill + same answer is treated as too similar', () {
      final candidate = fp('s', 'newparams', '4');
      expect(
        similarity.isTooSimilar(candidate,
            history: PracticeHistory.empty,
            sessionValues: const {},
            sessionAnswerSignatures: {candidate.answerSignature}),
        isTrue,
      );
    });

    test('history caps at maxEntries', () {
      var history = PracticeHistory.empty;
      history = history.withAll([
        for (var i = 0; i < PracticeHistory.maxEntries + 50; i++)
          fp('s', '$i', '$i'),
      ]);
      expect(history.recent.length, PracticeHistory.maxEntries);
      // The oldest were trimmed; the newest survive.
      expect(history.recent.last, contains('#${PracticeHistory.maxEntries + 49}'));
    });
  });

  group('Difficulty engine', () {
    const engine = DifficultyEngine();

    SkillMastery mastery(int points, {int attempts = 5, int correct = 4}) =>
        SkillMastery(
            skillId: 's',
            masteryPoints: points,
            attempts: attempts,
            correct: correct);

    test('cold start is easy', () {
      expect(
        engine.centreFor(const SkillMastery(skillId: 's'), isPro: true),
        PracticeDifficulty.easy,
      );
    });

    test('free tier is clamped to hard; expert is Pro-only', () {
      // Mastered skill.
      final mastered = mastery(100);
      expect(engine.centreFor(mastered, isPro: false), PracticeDifficulty.hard);
      expect(
          engine.centreFor(mastered, isPro: true), PracticeDifficulty.expert);
      expect(
        engine.clampToTier(PracticeDifficulty.expert, isPro: false),
        PracticeDifficulty.hard,
      );
    });

    test('a shaky skill is eased back a notch', () {
      final shaky = mastery(75, attempts: 6, correct: 2); // 33% accuracy
      final centre = engine.centreFor(shaky, isPro: true);
      // Proficient by points, but eased below Hard because accuracy is shaky.
      expect(centre.index, lessThan(PracticeDifficulty.hard.index));
    });
  });

  group('Adaptive engine', () {
    const engine = AdaptiveEngine();

    PracticeProgress withWeakSkill(PracticeSkill skill) => PracticeProgress(
          skills: {
            skill.id: SkillMastery(
              skillId: skill.id,
              masteryPoints: 10,
              attempts: 5,
              correct: 1,
            ),
          },
        );

    test('weakness profile ranks low-accuracy skills', () {
      final profile = engine.weaknessProfile(
        withWeakSkill(PracticeSkill.linearTwoStep),
      );
      expect(profile.hasSignal, isTrue);
      expect(profile.weakest!.skill, PracticeSkill.linearTwoStep);
    });

    test('free plan only ever contains free skills', () {
      final plan = engine.plan(
        request: const PracticeRequest(
            topic: PracticeTopic.algebra, questionCount: 8),
        progress: PracticeProgress.empty,
        isPro: false,
      );
      expect(plan, hasLength(8));
      for (final rec in plan) {
        expect(rec.skill.isFree, isTrue);
        expect(rec.difficulty.isPro, isFalse); // never expert for free
      }
    });

    test('Pro adaptive plan leads with the weak skill', () {
      final plan = engine.plan(
        request: const PracticeRequest(
            topic: PracticeTopic.algebra, adaptive: true),
        progress: withWeakSkill(PracticeSkill.linearTwoStep),
        isPro: true,
      );
      expect(plan.first.skill, PracticeSkill.linearTwoStep);
    });

    test('a pinned skill drives every slot (reinforcement)', () {
      final plan = engine.plan(
        request: PracticeRequest(
          topic: PracticeTopic.algebra,
          skillId: PracticeSkill.linearOneStep.id,
          questionCount: 4,
        ),
        progress: PracticeProgress.empty,
        isPro: false,
      );
      expect(plan.every((r) => r.skill == PracticeSkill.linearOneStep), isTrue);
    });

    test('a free user cannot pin a Pro skill (downgraded)', () {
      final plan = engine.plan(
        request: PracticeRequest(
          topic: PracticeTopic.algebra,
          skillId: PracticeSkill.quadraticFactor.id, // Pro-only
          questionCount: 3,
        ),
        progress: PracticeProgress.empty,
        isPro: false,
      );
      expect(plan.any((r) => r.skill == PracticeSkill.quadraticFactor), isFalse);
      expect(plan.every((r) => r.skill.isFree), isTrue);
    });
  });

  group('AdaptivePracticeService', () {
    test('free session builds only free-skill questions, all solvable',
        () async {
      final service = _service();
      final session = await service.createSession(
        const PracticeRequest(topic: PracticeTopic.algebra, questionCount: 6),
      );
      expect(session.questions, hasLength(6));
      for (final q in session.questions) {
        final skill = PracticeSkill.byId(q.skillId);
        expect(skill?.isFree ?? true, isTrue);
        expect(q.evaluate(q.correctAnswerText), isTrue);
      }
      // Unique ids within the session (so mastery attribution is unambiguous).
      final ids = session.questions.map((q) => q.id).toSet();
      expect(ids, hasLength(session.questions.length));
    });

    test('anti-repetition avoids exact repeats across two sessions', () async {
      final history = _MemoryHistoryStore();
      final service = _service(history: history, seed: 42);
      final first = await service.createSession(
        const PracticeRequest(topic: PracticeTopic.algebra, questionCount: 6),
      );
      final second = await service.createSession(
        const PracticeRequest(topic: PracticeTopic.algebra, questionCount: 6),
      );
      String key(PracticeQuestion q) =>
          '${q.skillId}#${GeneratedQuestion.content(q).fingerprint.signature}';
      final firstKeys = first.questions.map(key).toSet();
      for (final q in second.questions) {
        expect(firstKeys.contains(key(q)), isFalse,
            reason: 'no exact repeat of ${q.prompt}');
      }
      expect(history.load().recent, isNotEmpty);
    });

    test('Pro calculus uses the AI generator when available', () async {
      final ai = _FakeAiGenerator();
      final service = _service(isPro: true, ai: ai);
      final session = await service.createSession(
        const PracticeRequest(topic: PracticeTopic.calculus, questionCount: 4),
      );
      expect(session.questions, hasLength(4));
      expect(ai.calls, greaterThan(0));
      expect(session.questions.any((q) => q.prompt.startsWith('AI question')),
          isTrue);
    });

    test('Pro calculus falls back to the bank when AI is unavailable',
        () async {
      final service = _service(isPro: true); // no AI generator
      final session = await service.createSession(
        const PracticeRequest(topic: PracticeTopic.calculus, questionCount: 3),
      );
      expect(session.questions, isNotEmpty);
      for (final q in session.questions) {
        expect(q.evaluate(q.correctAnswerText), isTrue);
      }
    });

    test('respects the requested difficulty (clamped for free)', () async {
      final service = _service();
      final session = await service.createSession(
        const PracticeRequest(
          topic: PracticeTopic.algebra,
          difficulty: PracticeDifficulty.expert, // not allowed for free
          questionCount: 4,
        ),
      );
      for (final q in session.questions) {
        expect(q.difficulty, PracticeDifficulty.hard); // clamped down
      }
    });
  });

  group('AI response mapper', () {
    test('builds valid questions and drops malformed ones', () {
      final questions = PracticeQuestionMapper.fromResponse(
        {
          'questions': [
            {
              'prompt': 'Differentiate 3x^2',
              'type': 'input',
              'acceptedAnswers': ['6x'],
              'explanation': 'Power rule.',
            },
            {
              // choice with no correct option → dropped
              'prompt': 'Pick one',
              'type': 'multipleChoice',
              'options': [
                {'text': 'a', 'isCorrect': false},
                {'text': 'b', 'isCorrect': false},
              ],
              'explanation': 'x',
            },
            {
              // typed with no accepted answers → dropped
              'prompt': 'No answer',
              'type': 'input',
              'explanation': 'x',
            },
          ],
        },
        skill: PracticeSkill.calculusDerivative,
        difficulty: PracticeDifficulty.hard,
        nextId: () => 'id',
      );
      expect(questions, hasLength(1));
      expect(questions.single.skillId, PracticeSkill.calculusDerivative.id);
      expect(questions.single.evaluate('6x'), isTrue);
    });
  });

  group('Per-skill mastery + history persistence (domain)', () {
    test('SkillMastery.record grows only on correct answers', () {
      var m = const SkillMastery(skillId: 's');
      m = m.record(isCorrect: true, masteryGain: 5, epochDay: 1);
      expect(m.masteryPoints, 5);
      expect(m.attempts, 1);
      expect(m.correct, 1);
      m = m.record(isCorrect: false, masteryGain: 5, epochDay: 2);
      expect(m.masteryPoints, 5); // no growth on a wrong answer
      expect(m.attempts, 2);
      expect(m.level, MasteryLevel.beginner);
      expect(m.accuracy, closeTo(0.5, 1e-9));
    });
  });

  group('PracticeMistake', () {
    test('tutor seed message carries the learner + correct answers', () {
      const question = PracticeQuestion(
        id: 'q',
        topic: PracticeTopic.algebra,
        difficulty: PracticeDifficulty.medium,
        type: PracticeQuestionType.equation,
        prompt: 'Solve for x',
        promptLatex: '2x + 5 = 13',
        acceptedAnswers: ['4'],
        explanation: 'x = 4.',
      );
      const mistake =
          PracticeMistake(question: question, submittedAnswer: '3');
      expect(mistake.correctAnswer, '4');
      expect(mistake.tutorSeedMessage, contains('3'));
      expect(mistake.tutorSeedMessage, contains('4'));
      expect(mistake.problemLatex, '2x + 5 = 13');
    });
  });

  group('Analytics events', () {
    test('Stage 15 factories carry the expected names + params', () {
      expect(
        AnalyticsEvent.questionGenerated(
                topic: 'algebra', difficulty: 'easy', count: 5)
            .name,
        'question_generated',
      );
      expect(
        AnalyticsEvent.masteryIncreased(topic: 'algebra', level: 2).parameters,
        {'topic': 'algebra', 'level': 2},
      );
      expect(AnalyticsEvent.dailyChallengeCompleted().name,
          'daily_challenge_completed');
      expect(
        AnalyticsEvent.adaptiveRecommendationUsed(topic: 'fractions').name,
        'adaptive_recommendation_used',
      );
    });
  });
}
