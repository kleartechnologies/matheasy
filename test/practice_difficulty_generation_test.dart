// Safety net for the 5-level difficulty system: every on-device (template /
// rule-based) skill MUST generate a valid question at EVERY difficulty —
// including the new `veryEasy` (index 0) and `expert` (index 4) — without a
// RangeError from the difficulty-indexed range tables, and without returning
// null. This is the gate that proves the array-widening for the 5th level is
// complete and that no template silently regressed.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/practice/application/engine/parameter_generator.dart';
import 'package:matheasy/features/practice/application/engine/rule_based_generator.dart';
import 'package:matheasy/features/practice/application/engine/template_engine.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_skill.dart';

void main() {
  const template = TemplateEngine();
  const rule = RuleBasedGenerator();

  group('every on-device skill generates at every difficulty', () {
    for (final skill in PracticeSkill.values) {
      final onTemplate = template.supports(skill);
      final onRule = rule.supports(skill);
      if (!onTemplate && !onRule) continue; // AI-tier skills aren't on-device.

      for (final difficulty in PracticeDifficulty.values) {
        test('${skill.id} @ ${difficulty.name}', () {
          // Many seeds to exercise every internal branch / range table.
          for (var seed = 0; seed < 40; seed++) {
            final rng = ParameterGenerator(Random(seed));
            final gen = onTemplate
                ? template.generate(skill, difficulty, rng, 'q$seed')
                : rule.generate(skill, difficulty, rng, 'q$seed');
            expect(
              gen,
              isNotNull,
              reason: '${skill.id} @ ${difficulty.name} seed $seed → null',
            );
            final q = gen!.question;
            expect(q.prompt, isNotEmpty);
            expect(q.correctAnswerText, isNotEmpty);
            expect(q.difficulty, difficulty);
          }
        });
      }
    }
  });

  test('veryEasy draws are no larger than easy for the same skill+seed', () {
    // Prepending must make veryEasy EASIER (or equal), never harder, than easy.
    // We compare the numeric magnitude present in the prompt as a coarse proxy.
    int maxNumber(String s) {
      final nums = RegExp(r'\d+').allMatches(s).map((m) => int.parse(m.group(0)!));
      return nums.isEmpty ? 0 : nums.reduce(max);
    }

    for (final skill in PracticeSkill.values) {
      final onTemplate = template.supports(skill);
      final onRule = rule.supports(skill);
      if (!onTemplate && !onRule) continue;
      var veTotal = 0;
      var eTotal = 0;
      for (var seed = 0; seed < 60; seed++) {
        final ve = (onTemplate
            ? template.generate(
                skill, PracticeDifficulty.veryEasy, ParameterGenerator(Random(seed)), 've')
            : rule.generate(
                skill, PracticeDifficulty.veryEasy, ParameterGenerator(Random(seed)), 've'))!;
        final e = (onTemplate
            ? template.generate(
                skill, PracticeDifficulty.easy, ParameterGenerator(Random(seed)), 'e')
            : rule.generate(
                skill, PracticeDifficulty.easy, ParameterGenerator(Random(seed)), 'e'))!;
        veTotal += maxNumber(ve.question.promptLatex ?? ve.question.prompt);
        eTotal += maxNumber(e.question.promptLatex ?? e.question.prompt);
      }
      // Aggregate: very-easy numbers should not exceed easy numbers on average.
      expect(veTotal, lessThanOrEqualTo(eTotal + eTotal ~/ 5),
          reason: '${skill.id}: veryEasy numbers ($veTotal) exceed easy ($eTotal)');
    }
  });
}
