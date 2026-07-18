import '../../domain/practice_difficulty.dart';
import '../../domain/practice_question.dart';
import '../../domain/practice_skill.dart';
import 'generated_question.dart';
import 'parameter_generator.dart';
import 'practice_math.dart';

/// A parametric question generator for one skill: given a difficulty, an RNG and
/// a unique id, it produces a [GeneratedQuestion].
typedef QuestionTemplate = GeneratedQuestion Function(
  PracticeSkill skill,
  PracticeDifficulty difficulty,
  ParameterGenerator rng,
  String id,
);

/// Tier 1 — template + randomized-parameter generation. Instant, on-device, no
/// network, effectively unlimited variations. Backs every free-tier skill plus
/// the Pro advanced-algebra skills (both-sides, simultaneous, quadratics).
///
/// Each template is a pure function of (difficulty, rng): seed the rng and the
/// output is fully deterministic, which is how the engine is tested.
class TemplateEngine {
  const TemplateEngine();

  static final Map<String, QuestionTemplate> _templates = {
    PracticeSkill.linearOneStep.id: _linearOneStep,
    PracticeSkill.linearTwoStep.id: _linearTwoStep,
    PracticeSkill.evaluateExpression.id: _evaluateExpression,
    PracticeSkill.linearBothSides.id: _linearBothSides,
    PracticeSkill.simultaneousEquations.id: _simultaneous,
    PracticeSkill.quadraticFactor.id: _quadratic,
    PracticeSkill.fractionAddLike.id: _fractionAddLike,
    PracticeSkill.fractionAddUnlike.id: _fractionAddUnlike,
    PracticeSkill.fractionSimplify.id: _fractionSimplify,
    PracticeSkill.arithmeticOrderOps.id: _orderOfOps,
    PracticeSkill.percentOfQuantity.id: _percent,
    PracticeSkill.ratioSimplify.id: _ratio,
  };

  bool supports(PracticeSkill skill) => _templates.containsKey(skill.id);

  /// Generates a question for [skill], or `null` if this engine can't (the skill
  /// belongs to another tier).
  GeneratedQuestion? generate(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) =>
      _templates[skill.id]?.call(skill, difficulty, rng, id);

  // ---- Shared builders -----------------------------------------------------

  /// Difficulty tier as 0 (easy) … 3 (expert), for range scaling.
  static int _tier(PracticeDifficulty d) => d.index;

  /// Four multiple-choice options for an integer [correct], with near-miss
  /// distractors. Deterministic given [rng].
  static List<PracticeOption> _intOptions(
    int correct,
    ParameterGenerator rng, {
    int spread = 4,
  }) {
    final values = <int>{correct};
    var guard = 0;
    while (values.length < 4 && guard < 40) {
      final delta = rng.nonZeroBetween(-spread - 1, spread + 1);
      values.add(correct + delta);
      guard++;
    }
    final shuffled = rng.shuffled(values.toList());
    return [
      for (final v in shuffled)
        PracticeOption('$v', isCorrect: v == correct),
    ];
  }

  /// Four options from string [correct] + explicit [distractors] (deduped).
  static List<PracticeOption> _stringOptions(
    String correct,
    List<String> distractors,
    ParameterGenerator rng,
  ) {
    final values = <String>{correct};
    for (final d in distractors) {
      if (values.length >= 4) break;
      values.add(d);
    }
    final shuffled = rng.shuffled(values.toList());
    return [
      for (final v in shuffled) PracticeOption(v, isCorrect: v == correct),
    ];
  }

  // ---- Algebra: one-step ---------------------------------------------------

  static GeneratedQuestion _linearOneStep(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final maxVal = [5, 8, 15, 30, 50][tier];
    final form = rng.pick(['add', 'sub', 'mul']);
    final x = rng.between(2, maxVal);

    late final String latex;
    late final String explanation;
    late final String signature;

    switch (form) {
      case 'mul':
        final a = rng.between(2, [3, 4, 6, 9, 12][tier]);
        final c = a * x;
        latex = '${a}x = $c';
        explanation = 'Divide both sides by $a: x = $c ÷ $a = $x.';
        signature = 'mul|$a|$x';
      case 'sub':
        final b = rng.between(1, maxVal);
        final c = x - b;
        latex = 'x - $b = $c';
        explanation = 'Add $b to both sides: x = $c + $b = $x.';
        signature = 'sub|$b|$x';
      case _: // add
        final b = rng.between(1, maxVal);
        final c = x + b;
        latex = 'x + $b = $c';
        explanation = 'Subtract $b from both sides: x = $c − $b = $x.';
        signature = 'add|$b|$x';
    }

    final asChoice = rng.chance(0.4);
    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: asChoice
          ? PracticeQuestionType.multipleChoice
          : PracticeQuestionType.equation,
      prompt: 'Solve for x',
      promptLatex: latex,
      explanation: explanation,
      skillId: skill.id,
      options: asChoice ? _intOptions(x, rng) : const [],
      acceptedAnswers: asChoice ? const [] : ['$x', 'x=$x'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Algebra: two-step (ax + b = c) --------------------------------------

  static GeneratedQuestion _linearTwoStep(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final a = rng.between(2, [3, 4, 6, 8, 12][tier]);
    final x = rng.between(2, [4, 6, 9, 12, 20][tier]);
    // Allow subtraction (and negative constants) at higher tiers.
    final subtract = tier >= 2 && rng.chance();
    final b = rng.between(1, [6, 9, 12, 20, 40][tier]);
    final c = subtract ? a * x - b : a * x + b;
    final op = subtract ? '-' : '+';
    final latex = '${a}x $op $b = $c';
    final explanation = subtract
        ? 'Add $b: ${a}x = ${a * x}. Divide by $a: x = $x.'
        : 'Subtract $b: ${a}x = ${a * x}. Divide by $a: x = $x.';
    final signature = 'two|$a|$b|${subtract ? 's' : 'a'}|$x';

    final asChoice = rng.chance(0.35);
    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: asChoice
          ? PracticeQuestionType.multipleChoice
          : PracticeQuestionType.equation,
      prompt: 'Solve for x',
      promptLatex: latex,
      explanation: explanation,
      skillId: skill.id,
      options: asChoice ? _intOptions(x, rng) : const [],
      acceptedAnswers: asChoice ? const [] : ['$x', 'x=$x'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Algebra: evaluate an expression -------------------------------------

  static GeneratedQuestion _evaluateExpression(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final a = rng.between(2, [4, 6, 9, 12, 20][tier]);
    final b = rng.between(1, [6, 9, 15, 25, 40][tier]);
    final x = rng.between(2, [5, 8, 12, 15, 25][tier]);
    final withConstant = tier >= 2;
    final value = withConstant ? a * x + b : a * x;
    final latex = withConstant ? '${a}x + $b' : '${a}x';
    final explanation = withConstant
        ? 'Substitute x = $x: $a × $x + $b = ${a * x} + $b = $value.'
        : 'Substitute x = $x: $a × $x = $value.';
    final signature = 'eval|$a|${withConstant ? b : 0}|$x';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'Find the value of the expression when x = $x',
      promptLatex: latex,
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$value'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Algebra (Pro): variables on both sides ------------------------------

  static GeneratedQuestion _linearBothSides(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    // ax + b = cx + d with a > c and an integer solution x. Keeping a > c makes
    // the constant d = (a-c)x + b strictly positive, so the equation renders
    // cleanly (no "+ -6" / "+ 0") and "divide by (a-c)" is always by a positive.
    final x = rng.between(2, [5, 8, 10, 12, 20][tier]);
    final c = rng.between(1, [3, 4, 6, 8, 10][tier]);
    final a = c + rng.between(1, [3, 4, 6, 8, 10][tier]);
    final b = rng.between(1, [6, 9, 12, 20, 30][tier]);
    // d chosen so both sides equal at x: ax + b = cx + d  =>  d = (a-c)x + b.
    final d = (a - c) * x + b;
    final latex = '${a}x + $b = ${c}x + $d';
    final explanation =
        'Subtract ${c}x from both sides: ${a - c}x + $b = $d. '
        'Subtract $b: ${a - c}x = ${d - b}. Divide by ${a - c}: x = $x.';
    final signature = 'both|$a|$b|$c|$d';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.equation,
      prompt: 'Solve for x',
      promptLatex: latex,
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$x', 'x=$x'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Algebra (Pro): simultaneous equations -------------------------------

  static GeneratedQuestion _simultaneous(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final x = rng.between(1, [5, 8, 10, 14, 20][tier]);
    final y = rng.between(1, [5, 8, 10, 14, 20][tier]);
    final s = x + y;
    final diff = x - y;
    // x + y = s ; x - y = diff  =>  ask for x.
    final latex = 'x + y = $s,\\quad x - y = $diff';
    final explanation =
        'Add the equations: 2x = ${s + diff}, so x = $x. '
        '(Then y = $y.)';
    final signature = 'sim|$s|$diff';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'Find x',
      promptLatex: latex,
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$x', 'x=$x'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Algebra (Pro): factorising quadratics -------------------------------

  static GeneratedQuestion _quadratic(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    // (x - r1)(x - r2) = 0  =>  x^2 - (r1+r2)x + r1*r2 = 0
    final r1 = rng.between(1, [3, 5, 7, 9, 12][tier]);
    final r2 = rng.between(1, [3, 5, 7, 9, 12][tier]);
    final sum = r1 + r2;
    final product = r1 * r2;
    final bTerm = sum == 0
        ? ''
        : (sum > 0 ? ' - ${sum}x' : ' + ${sum.abs()}x');
    final latex = 'x^2$bTerm + $product = 0';
    // Give one root, ask for the other (single-answer, unambiguous).
    final given = r1;
    final other = r2;
    final explanation =
        'Factor: (x − $r1)(x − $r2) = 0. The solutions are x = $r1 and '
        'x = $r2.';
    final signature = 'quad|$r1|$r2';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'One solution is x = $given. What is the other solution for x?',
      promptLatex: latex,
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$other', 'x=$other'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Fractions: add like denominators ------------------------------------

  static GeneratedQuestion _fractionAddLike(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final d = rng.between(3, [4, 6, 9, 12, 15][tier]);
    final a = rng.between(1, d - 1);
    final b = rng.between(1, d - 1);
    final answer = PracticeMath.formatFraction(a + b, d);
    final latex = r'\frac{' '$a' r'}{' '$d' r'} + \frac{' '$b' r'}{' '$d' r'}';
    final explanation = 'Same denominator: add the tops — '
        '($a + $b)/$d = ${a + b}/$d = $answer.';
    final signature = 'fadd|$a|$b|$d';

    // All distractors are reduced (like the answer), so any that happen to be
    // value-equal to the correct answer collapse to the same string and are
    // de-duplicated by [_stringOptions] rather than shown as a "wrong" option
    // that is actually right (e.g. 2/6 + 2/6 → answer 2/3, distractor 4/6).
    final distractors = <String>[
      PracticeMath.formatFraction(a + b, d * 2),
      PracticeMath.formatFraction(a + b, d + 1),
      PracticeMath.formatFraction(a * b, d),
    ];
    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Add the fractions',
      promptLatex: latex,
      spokenPrompt: '$a over $d plus $b over $d',
      explanation: explanation,
      skillId: skill.id,
      options: _stringOptions(answer, distractors, rng),
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Fractions: add unlike denominators ----------------------------------

  static GeneratedQuestion _fractionAddUnlike(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final b = rng.between(2, [3, 4, 6, 8, 10][tier]);
    var d = rng.between(2, [3, 5, 7, 9, 12][tier]);
    if (d == b) d += 1;
    final a = rng.between(1, b - 1 < 1 ? 1 : b - 1);
    final c = rng.between(1, d - 1 < 1 ? 1 : d - 1);
    final numerator = a * d + c * b;
    final denominator = b * d;
    final answer = PracticeMath.formatFraction(numerator, denominator);
    final latex = r'\frac{' '$a' r'}{' '$b' r'} + \frac{' '$c' r'}{' '$d' r'}';
    // Use b×d as the common denominator so the shown working is self-consistent
    // (it always is a common denominator; not necessarily the least).
    final explanation =
        'Common denominator $denominator: $a/$b + $c/$d = '
        '$numerator/$denominator = $answer.';
    final signature = 'faddu|$a|$b|$c|$d';

    // Reduced distractors (see _fractionAddLike) so a value-equal wrong option
    // can never be presented as incorrect.
    final distractors = <String>[
      PracticeMath.formatFraction(a + c, b + d),
      PracticeMath.formatFraction(numerator + 1, denominator),
      PracticeMath.formatFraction(a + c, b * d),
    ];
    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Add the fractions',
      promptLatex: latex,
      spokenPrompt: '$a over $b plus $c over $d',
      explanation: explanation,
      skillId: skill.id,
      options: _stringOptions(answer, distractors, rng),
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Fractions: simplify -------------------------------------------------

  static GeneratedQuestion _fractionSimplify(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    // Build a reduced p/q, then scale by k so it needs simplifying.
    var p = rng.between(1, [3, 4, 6, 8, 10][tier]);
    var q = rng.between(p + 1, [5, 8, 12, 15, 20][tier]);
    final g = PracticeMath.gcd(p, q);
    p = p ~/ g;
    q = q ~/ g;
    final k = rng.between(2, [3, 4, 5, 6, 8][tier]);
    final n = p * k;
    final den = q * k;
    final answer = PracticeMath.formatFraction(p, q);
    final explanation = 'Divide top and bottom by their common factor $k: '
        '$n/$den = $answer.';
    final signature = 'fsimp|$n|$den';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'Simplify $n/$den to lowest terms',
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: [answer, answer.replaceAll('/', ' / ')],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Arithmetic: order of operations -------------------------------------

  static GeneratedQuestion _orderOfOps(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final a = rng.between(2, [6, 9, 15, 20, 30][tier]);
    final b = rng.between(2, [4, 6, 9, 12, 15][tier]);
    final c = rng.between(2, [4, 6, 9, 12, 15][tier]);
    // a + b × c  (multiplication first).
    final multFirst = rng.chance(0.6);
    late final int value;
    late final String latex;
    late final String explanation;
    if (multFirst) {
      value = a + b * c;
      latex = '$a + $b \\times $c';
      explanation = 'Multiply first: $b × $c = ${b * c}, then add $a = $value.';
    } else {
      value = a * b - c;
      latex = '$a \\times $b - $c';
      explanation = 'Multiply first: $a × $b = ${a * b}, then subtract $c = '
          '$value.';
    }
    final signature = 'ops|${multFirst ? 'm' : 's'}|$a|$b|$c';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'Evaluate using the correct order of operations',
      promptLatex: latex,
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$value'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Percentages ---------------------------------------------------------

  static GeneratedQuestion _percent(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final percent = rng.pick(
      [
        [10, 25, 50],
        [10, 20, 25, 50],
        [10, 15, 20, 25, 40, 50],
        [5, 12, 15, 30, 60, 75],
        [8, 12, 35, 45, 65, 85],
      ][tier],
    );
    // Choose n so percent% of n is an integer.
    final base = 100 ~/ PracticeMath.gcd(percent, 100);
    final n = base * rng.between(1, [4, 6, 8, 10, 12][tier]);
    final value = percent * n ~/ 100;
    final explanation = '$percent% of $n = ($percent ÷ 100) × $n = $value.';
    final signature = 'pct|$percent|$n';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'What is $percent% of $n?',
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$value'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Ratios --------------------------------------------------------------

  static GeneratedQuestion _ratio(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    // Build a reduced p:q, scale by k.
    var p = rng.between(1, [3, 5, 7, 9, 12][tier]);
    var q = rng.between(1, [3, 5, 7, 9, 12][tier]);
    final g0 = PracticeMath.gcd(p, q);
    p = p ~/ g0;
    q = q ~/ g0;
    final k = rng.between(2, [3, 5, 6, 8, 10][tier]);
    final a = p * k;
    final b = q * k;
    final answer = '$p:$q';
    final explanation = 'Divide both parts by their common factor $k: '
        '$a:$b = $answer.';
    final signature = 'ratio|$a|$b';

    final distractors = <String>['$a:$b', '$q:$p', '${p + 1}:$q'];
    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Simplify the ratio $a : $b to its simplest form',
      explanation: explanation,
      skillId: skill.id,
      options: _stringOptions(answer, distractors, rng),
    );
    return GeneratedQuestion.of(question, signature: signature);
  }
}
