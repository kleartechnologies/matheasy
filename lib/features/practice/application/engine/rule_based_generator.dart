import '../../domain/practice_difficulty.dart';
import '../../domain/practice_question.dart';
import '../../domain/practice_skill.dart';
import 'generated_question.dart';
import 'parameter_generator.dart';
import 'practice_math.dart';

/// A rule-based generator for one skill.
typedef RuleTemplate = GeneratedQuestion Function(
  PracticeSkill skill,
  PracticeDifficulty difficulty,
  ParameterGenerator rng,
  String id,
);

/// Tier 2 — rule / constraint-based generation. Still 100% on-device, but the
/// questions are built from mathematical constraints rather than a fixed
/// algebraic template: triangles whose angles must sum to 180°, Pythagorean
/// triples, data sets with a whole-number mean, ratio-based probabilities.
///
/// Geometry, measurement, trigonometry, statistics and probability — all
/// Pro-only skills. Pure functions of (difficulty, rng), same as [TemplateEngine].
class RuleBasedGenerator {
  const RuleBasedGenerator();

  /// Common Pythagorean triples, by (leg, leg, hypotenuse).
  static const List<List<int>> _triples = [
    [3, 4, 5],
    [6, 8, 10],
    [5, 12, 13],
    [8, 15, 17],
    [9, 12, 15],
    [7, 24, 25],
    [20, 21, 29],
  ];

  static final Map<String, RuleTemplate> _templates = {
    PracticeSkill.triangleAngle.id: _triangleAngle,
    PracticeSkill.rectangleArea.id: _rectangleArea,
    PracticeSkill.pythagoras.id: _pythagoras,
    PracticeSkill.trigRatio.id: _trigRatio,
    PracticeSkill.statsMean.id: _mean,
    PracticeSkill.statsMedianMode.id: _medianMode,
    PracticeSkill.probabilitySingle.id: _probability,
  };

  bool supports(PracticeSkill skill) => _templates.containsKey(skill.id);

  GeneratedQuestion? generate(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) =>
      _templates[skill.id]?.call(skill, difficulty, rng, id);

  static int _tier(PracticeDifficulty d) => d.index;

  // ---- Geometry: triangle angles -------------------------------------------

  static GeneratedQuestion _triangleAngle(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    // Two angles that leave a positive third.
    final a = rng.between(30, 90);
    final b = rng.between(20, 150 - a);
    final third = 180 - a - b;
    final explanation = 'Angles in a triangle sum to 180°: '
        '180 − $a − $b = $third°.';
    final signature = 'tri|$a|$b';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'A triangle has angles of $a° and $b°. '
          'What is the third angle, in degrees?',
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$third', '$third°', '$third degrees'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Geometry: area & perimeter ------------------------------------------

  static GeneratedQuestion _rectangleArea(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final l = rng.between(3, [10, 15, 20, 30][tier]);
    final w = rng.between(2, [8, 12, 16, 25][tier]);
    final askArea = rng.chance(0.6);
    final value = askArea ? l * w : 2 * (l + w);
    final explanation = askArea
        ? 'Area = length × width = $l × $w = $value.'
        : 'Perimeter = 2 × (length + width) = 2 × ($l + $w) = $value.';
    final signature = 'rect|${askArea ? 'a' : 'p'}|$l|$w';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: askArea
          ? 'What is the area of a rectangle $l by $w?'
          : 'What is the perimeter of a rectangle $l by $w?',
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$value'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Geometry: Pythagoras ------------------------------------------------

  static GeneratedQuestion _pythagoras(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final pool = _triples.take([3, 5, 6, 7][tier].clamp(1, _triples.length));
    final triple = rng.pick(pool.toList());
    final a = triple[0];
    final b = triple[1];
    final c = triple[2];
    final explanation = 'By Pythagoras: c = √($a² + $b²) = √${a * a + b * b} '
        '= $c.';
    final signature = 'pyth|$a|$b';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'A right triangle has legs $a and $b. '
          'What is the length of the hypotenuse?',
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$c'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Trigonometry: ratios ------------------------------------------------

  static GeneratedQuestion _trigRatio(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final triple = rng.pick(_triples.take(4).toList());
    final opposite = triple[0];
    final adjacent = triple[1];
    final hyp = triple[2];
    final ratio = rng.pick(['sin', 'cos', 'tan']);
    late final String answer;
    late final String explanation;
    switch (ratio) {
      case 'cos':
        answer = PracticeMath.formatFraction(adjacent, hyp);
        explanation = 'cos = adjacent ÷ hypotenuse = $adjacent/$hyp = $answer.';
      case 'tan':
        answer = PracticeMath.formatFraction(opposite, adjacent);
        explanation = 'tan = opposite ÷ adjacent = $opposite/$adjacent = '
            '$answer.';
      case _: // sin
        answer = PracticeMath.formatFraction(opposite, hyp);
        explanation = 'sin = opposite ÷ hypotenuse = $opposite/$hyp = $answer.';
    }
    final signature = 'trig|$ratio|$opposite|$adjacent|$hyp';

    final distractors = <String>[
      PracticeMath.formatFraction(adjacent, hyp),
      PracticeMath.formatFraction(opposite, adjacent),
      PracticeMath.formatFraction(hyp, opposite),
    ]..removeWhere((d) => d == answer);
    final options = <String>{answer, ...distractors}.take(4).toList();

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'A right triangle has opposite = $opposite, adjacent = '
          '$adjacent, hypotenuse = $hyp. What is $ratio of the angle?',
      explanation: explanation,
      skillId: skill.id,
      options: [
        for (final o in rng.shuffled(options))
          PracticeOption(o, isCorrect: o == answer),
      ],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Statistics: mean ----------------------------------------------------

  static GeneratedQuestion _mean(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final count = [3, 3, 4, 5][tier];
    final mean = rng.between(4, [10, 15, 20, 30][tier]);
    // Build `count` values around `mean` whose deltas sum to 0 (exact mean).
    final values = <int>[];
    var runningDelta = 0;
    for (var i = 0; i < count - 1; i++) {
      final delta = rng.nonZeroBetween(-mean + 1, mean);
      values.add(mean + delta);
      runningDelta += delta;
    }
    values.add(mean - runningDelta); // last value fixes the mean exactly.
    final list = rng.shuffled(values);
    final sum = list.fold(0, (a, b) => a + b);
    final explanation =
        'Mean = sum ÷ count = $sum ÷ $count = $mean.';
    final signature = 'mean|${list.join('_')}';

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'What is the mean of ${list.join(', ')}?',
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$mean'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Statistics: median / mode -------------------------------------------

  static GeneratedQuestion _medianMode(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final askMedian = rng.chance();
    final maxVal = [12, 20, 30, 50][tier];
    if (askMedian) {
      final count = [3, 5, 5, 7][tier];
      final values =
          [for (var i = 0; i < count; i++) rng.between(1, maxVal)];
      final sorted = [...values]..sort();
      final median = sorted[count ~/ 2];
      final explanation = 'Sort the values: ${sorted.join(', ')}. The middle '
          'value is $median.';
      final signature = 'median|${values.join('_')}';
      final question = PracticeQuestion(
        id: id,
        topic: skill.topic,
        difficulty: difficulty,
        type: PracticeQuestionType.input,
        prompt: 'What is the median of ${values.join(', ')}?',
        explanation: explanation,
        skillId: skill.id,
        acceptedAnswers: ['$median'],
      );
      return GeneratedQuestion.of(question, signature: signature);
    }
    // Mode: repeat one value so it's the clear mode.
    final mode = rng.between(1, maxVal);
    final others = rng
        .shuffled([for (var i = 0; i < 3; i++) rng.between(1, maxVal)])
        .where((v) => v != mode)
        .take(2)
        .toList();
    final values = rng.shuffled([mode, mode, mode, ...others]);
    final explanation = '$mode appears most often, so the mode is $mode.';
    final signature = 'mode|${values.join('_')}';
    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.input,
      prompt: 'What is the mode of ${values.join(', ')}?',
      explanation: explanation,
      skillId: skill.id,
      acceptedAnswers: ['$mode'],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }

  // ---- Probability ---------------------------------------------------------

  static GeneratedQuestion _probability(
    PracticeSkill skill,
    PracticeDifficulty difficulty,
    ParameterGenerator rng,
    String id,
  ) {
    final tier = _tier(difficulty);
    final red = rng.between(1, [4, 6, 8, 10][tier]);
    final blue = rng.between(1, [4, 6, 8, 10][tier]);
    final total = red + blue;
    final answer = PracticeMath.formatFraction(red, total);
    final explanation = 'P(red) = favourable ÷ total = $red/$total = $answer.';
    final signature = 'prob|$red|$blue';

    final distractors = <String>[
      PracticeMath.formatFraction(blue, total),
      PracticeMath.formatFraction(red, blue),
      '$red/$blue',
    ]..removeWhere((d) => d == answer);
    final options = <String>{answer, ...distractors}.take(4).toList();

    final question = PracticeQuestion(
      id: id,
      topic: skill.topic,
      difficulty: difficulty,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'A bag has $red red and $blue blue marbles. '
          'What is the probability of drawing a red marble?',
      explanation: explanation,
      skillId: skill.id,
      options: [
        for (final o in rng.shuffled(options))
          PracticeOption(o, isCorrect: o == answer),
      ],
    );
    return GeneratedQuestion.of(question, signature: signature);
  }
}
