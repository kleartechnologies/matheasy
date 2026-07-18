// The deterministic 5-level difficulty system: the spec (strict rules), the
// per-question metadata (incl. the withId silent-drop trap), the concept-floor
// validator, and the "difficulty is the user's choice, held constant" contract.

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/practice/application/engine/difficulty_validator.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_skill.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';

PracticeQuestion _q({
  PracticeDifficulty difficulty = PracticeDifficulty.medium,
  String? skillId,
  int? estimatedSteps,
  int? estimatedSolveTimeSeconds,
  String? subtopic,
  String? gradeLevel,
}) =>
    PracticeQuestion(
      id: 'q1',
      topic: PracticeTopic.algebra,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'Solve',
      explanation: 'because',
      acceptedAnswers: const ['3'],
      skillId: skillId,
      estimatedSteps: estimatedSteps,
      estimatedSolveTimeSeconds: estimatedSolveTimeSeconds,
      subtopic: subtopic,
      gradeLevel: gradeLevel,
    );

void main() {
  group('PracticeDifficulty — 5 levels, gating, spec', () {
    test('exactly five levels, easiest first', () {
      expect(PracticeDifficulty.values, hasLength(5));
      expect(PracticeDifficulty.values.first, PracticeDifficulty.veryEasy);
      expect(PracticeDifficulty.values.last, PracticeDifficulty.expert);
    });

    test('Hard + Expert are Pro; Very Easy / Easy / Medium are free', () {
      expect(PracticeDifficulty.veryEasy.isPro, isFalse);
      expect(PracticeDifficulty.easy.isPro, isFalse);
      expect(PracticeDifficulty.medium.isPro, isFalse);
      expect(PracticeDifficulty.hard.isPro, isTrue);
      expect(PracticeDifficulty.expert.isPro, isTrue);
    });

    test('every level carries a complete, monotonic spec', () {
      var lastSteps = 0;
      var lastMax = 0;
      var lastTime = 0;
      for (final d in PracticeDifficulty.values) {
        final s = d.spec;
        expect(s.gradeLabel, isNotEmpty);
        expect(s.maxSteps, greaterThanOrEqualTo(s.targetSteps));
        // Harder levels never allow fewer steps / less time.
        expect(s.targetSteps, greaterThanOrEqualTo(lastSteps));
        expect(s.maxSteps, greaterThanOrEqualTo(lastMax));
        expect(s.estimatedSolveTimeSeconds, greaterThanOrEqualTo(lastTime));
        lastSteps = s.targetSteps;
        lastMax = s.maxSteps;
        lastTime = s.estimatedSolveTimeSeconds;
      }
      // Very Easy is primary-level: no negatives / fractions / algebra baked in.
      expect(PracticeDifficulty.veryEasy.spec.allowNegatives, isFalse);
      expect(PracticeDifficulty.veryEasy.spec.allowFractions, isFalse);
      expect(PracticeDifficulty.veryEasy.spec.allowAlgebra, isFalse);
    });

    test('atLeast raises to a floor but never lowers', () {
      expect(
        PracticeDifficulty.veryEasy.atLeast(PracticeDifficulty.medium),
        PracticeDifficulty.medium,
      );
      expect(
        PracticeDifficulty.hard.atLeast(PracticeDifficulty.easy),
        PracticeDifficulty.hard,
      );
    });
  });

  group('PracticeQuestion — difficulty metadata', () {
    test('getters fall back to the difficulty spec when unset', () {
      final q = _q(difficulty: PracticeDifficulty.hard);
      expect(q.steps, PracticeDifficulty.hard.spec.targetSteps);
      expect(q.solveTimeSeconds,
          PracticeDifficulty.hard.spec.estimatedSolveTimeSeconds);
      expect(q.grade, PracticeDifficulty.hard.spec.gradeLabel);
    });

    test('explicit metadata overrides the fallback', () {
      final q = _q(
        estimatedSteps: 4,
        estimatedSolveTimeSeconds: 99,
        gradeLevel: 'Custom',
      );
      expect(q.steps, 4);
      expect(q.solveTimeSeconds, 99);
      expect(q.grade, 'Custom');
    });

    test('subtopicLabel falls back to the skill label', () {
      final q = _q(skillId: 'alg_quadratic');
      expect(q.subtopicLabel, PracticeSkill.quadraticFactor.label);
    });

    test('metadata survives withId() — the silent-drop trap', () {
      final q = _q(
        estimatedSteps: 6,
        estimatedSolveTimeSeconds: 120,
        subtopic: 'Quadratics',
        gradeLevel: 'A-Level',
        skillId: 'alg_quadratic',
      );
      final restamped = q.withId('slot-7');
      expect(restamped.id, 'slot-7');
      expect(restamped.estimatedSteps, 6);
      expect(restamped.estimatedSolveTimeSeconds, 120);
      expect(restamped.subtopic, 'Quadratics');
      expect(restamped.gradeLevel, 'A-Level');
    });
  });

  group('DifficultyValidator + concept floor', () {
    const validator = DifficultyValidator();

    test('a quadratic is not allowed at Very Easy but is at Medium', () {
      expect(
        skillAllowedAt(
            PracticeSkill.quadraticFactor, PracticeDifficulty.veryEasy),
        isFalse,
      );
      expect(
        skillAllowedAt(
            PracticeSkill.quadraticFactor, PracticeDifficulty.medium),
        isTrue,
      );
    });

    test('rejects a question whose skill concept is above the level', () {
      final tooHard = _q(
        difficulty: PracticeDifficulty.veryEasy,
        skillId: 'alg_quadratic', // floor = medium
      );
      expect(validator.isValid(tooHard, PracticeDifficulty.veryEasy), isFalse);
    });

    test('rejects a level mismatch', () {
      final q = _q(difficulty: PracticeDifficulty.easy);
      expect(validator.isValid(q, PracticeDifficulty.medium), isFalse);
    });

    test('rejects a question over the step budget', () {
      final q = _q(
        difficulty: PracticeDifficulty.veryEasy, // maxSteps = 2
        skillId: 'alg_linear_1',
        estimatedSteps: 5,
      );
      expect(validator.isValid(q, PracticeDifficulty.veryEasy), isFalse);
    });

    test('accepts a well-fitted question', () {
      final q = _q(
        skillId: 'alg_quadratic', // floor = medium (the _q default level)
        estimatedSteps: 3,
      );
      expect(validator.isValid(q, PracticeDifficulty.medium), isTrue);
    });

    test('concept floors are ordered sanely', () {
      // A single-step skill floors at Very Easy; an inherently multi-step one
      // never floors below Medium.
      expect(conceptFloor(PracticeSkill.linearOneStep),
          PracticeDifficulty.veryEasy);
      expect(
        conceptFloor(PracticeSkill.simultaneousEquations).index,
        greaterThanOrEqualTo(PracticeDifficulty.medium.index),
      );
      expect(conceptFloor(PracticeSkill.calculusDerivative).index,
          greaterThanOrEqualTo(PracticeDifficulty.hard.index));
    });
  });

  test('every level round-trips its own grade band on a question', () {
    for (final d in PracticeDifficulty.values) {
      final q = PracticeQuestion(
        id: 'q',
        topic: PracticeTopic.algebra,
        difficulty: d,
        type: PracticeQuestionType.input,
        prompt: 'Solve',
        explanation: 'why',
        acceptedAnswers: const ['1'],
      );
      expect(q.difficulty, d);
      expect(q.grade, d.spec.gradeLabel);
    }
  });
}
