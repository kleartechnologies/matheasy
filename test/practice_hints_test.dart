// The V5 multi-stage hint content: every deterministic generator and every
// bank question ships a level-1 nudge + level-2 method pointer, no hint ever
// states the computed answer ("= 5"-style), and the per-topic fallbacks cover
// questions that carry no authored hints.
//
// NOTE the golden-rule nuance being tested: hints MAY quote numbers GIVEN in
// the question (which can coincidentally equal the answer — a 60-60-60
// triangle), but must never present the answer as a computed result. So the
// leak assertion targets the "= answer" form, not bare containment.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/practice/application/engine/parameter_generator.dart';
import 'package:matheasy/features/practice/application/engine/rule_based_generator.dart';
import 'package:matheasy/features/practice/application/engine/template_engine.dart';
import 'package:matheasy/features/practice/application/practice_question_bank.dart';
import 'package:matheasy/features/practice/domain/generation_tier.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_hint_fallbacks.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_skill.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';

/// Fails when a hint presents [answer] as a computed result ("= 5", "is 5.")
/// or announces it outright. Bare occurrences of the digits are allowed —
/// they can be givens the hint legitimately quotes.
void expectNoComputedAnswer(PracticeQuestion q, {required String context}) {
  final answer = q.correctAnswerText.trim().toLowerCase();
  if (answer.isEmpty) return;
  final escaped = RegExp.escape(answer);
  final computedForms = [
    RegExp('=\\s*$escaped(\\D|\$)'),
    RegExp('\\bis\\s+$escaped(\\D|\$)'),
    RegExp('\\banswer\\b.{0,12}$escaped'),
  ];
  for (final hint in q.hints) {
    final h = hint.toLowerCase();
    for (final form in computedForms) {
      expect(form.hasMatch(h), isFalse,
          reason: '$context: hint "$hint" states the answer "$answer"');
    }
  }
}

void main() {
  group('Template engine hints (Tier 1)', () {
    const engine = TemplateEngine();

    test('every template skill ships 2 hints, never stating the answer', () {
      final rng = ParameterGenerator(Random(42));
      final skills = PracticeSkill.values.where(engine.supports);
      expect(skills, isNotEmpty);
      for (final skill in skills) {
        for (final difficulty in PracticeDifficulty.values) {
          for (var i = 0; i < 20; i++) {
            final q = engine.generate(skill, difficulty, rng, 'id')!.question;
            expect(q.hints, hasLength(2),
                reason: '${skill.id} @ ${difficulty.name} ships both hints');
            expect(q.hints.every((h) => h.trim().isNotEmpty), isTrue,
                reason: '${skill.id} hints are non-empty');
            expectNoComputedAnswer(q,
                context: '${skill.id} @ ${difficulty.name}');
          }
        }
      }
    });
  });

  group('Rule-based engine hints (Tier 2)', () {
    const engine = RuleBasedGenerator();

    test('every rule skill ships 2 hints, never stating the answer', () {
      final rng = ParameterGenerator(Random(7));
      final skills = PracticeSkill.values
          .where((s) => s.tier == GenerationTier.ruleBased);
      expect(skills, isNotEmpty);
      for (final skill in skills) {
        for (final difficulty in PracticeDifficulty.values) {
          for (var i = 0; i < 20; i++) {
            final q = engine.generate(skill, difficulty, rng, 'id')!.question;
            expect(q.hints, hasLength(2),
                reason: '${skill.id} @ ${difficulty.name} ships both hints');
            expect(q.hints.every((h) => h.trim().isNotEmpty), isTrue,
                reason: '${skill.id} hints are non-empty');
            expectNoComputedAnswer(q,
                context: '${skill.id} @ ${difficulty.name}');
          }
        }
      }
    });
  });

  group('Question bank hints', () {
    test('every bank question ships 2 hints, never stating the answer', () {
      for (final topic in PracticeTopic.values) {
        for (final q in PracticeQuestionBank.forTopic(topic)) {
          expect(q.hints, hasLength(2), reason: '${q.id} ships both hints');
          expect(q.hints.every((h) => h.trim().isNotEmpty), isTrue,
              reason: '${q.id} hints are non-empty');
          expectNoComputedAnswer(q, context: q.id);
        }
      }
    });
  });

  group('PracticeHintFallbacks', () {
    PracticeQuestion question({List<String> hints = const []}) =>
        PracticeQuestion(
          id: 'q',
          topic: PracticeTopic.geometry,
          difficulty: PracticeDifficulty.medium,
          type: PracticeQuestionType.input,
          prompt: 'p',
          explanation: 'e',
          acceptedAnswers: const ['1'],
          hints: hints,
        );

    test('authored hints win when complete', () {
      final q = question(hints: const ['nudge', 'method']);
      expect(PracticeHintFallbacks.hintsFor(q), ['nudge', 'method']);
    });

    test('empty hints fall back to the topic pair', () {
      final hints = PracticeHintFallbacks.hintsFor(question());
      expect(hints, hasLength(2));
      expect(hints.every((h) => h.isNotEmpty), isTrue);
    });

    test('a single authored hint is topped up from the fallback', () {
      final hints =
          PracticeHintFallbacks.hintsFor(question(hints: const ['nudge']));
      expect(hints, hasLength(2));
      expect(hints.first, 'nudge');
      expect(hints[1], isNotEmpty);
    });

    test('every topic has a fallback pair', () {
      for (final topic in PracticeTopic.values) {
        final q = PracticeQuestion(
          id: 'q',
          topic: topic,
          difficulty: PracticeDifficulty.easy,
          type: PracticeQuestionType.input,
          prompt: 'p',
          explanation: 'e',
          acceptedAnswers: const ['1'],
        );
        expect(PracticeHintFallbacks.hintsFor(q), hasLength(2),
            reason: topic.name);
      }
    });
  });
}
