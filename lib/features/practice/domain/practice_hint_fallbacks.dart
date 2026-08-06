import 'practice_question.dart';
import 'practice_topic.dart';

/// Generic level-1/level-2 hint pairs, used when a question carries no authored
/// [PracticeQuestion.hints] (bank questions predating hints, cached AI
/// questions, or an AI hint dropped by the server's answer-leak screen).
///
/// Same golden rule as authored hints: method pointers only, no arithmetic —
/// deeper help (first step, full solution) comes from the verified solve
/// pipeline, never from these strings.
abstract final class PracticeHintFallbacks {
  /// The hints to show for [question]: its own when present, else a per-topic
  /// generic pair. Always returns exactly two entries.
  static List<String> hintsFor(PracticeQuestion question) {
    if (question.hints.length >= 2) return question.hints;
    final generic = _byTopic[question.topic] ?? _general;
    if (question.hints.isEmpty) return generic;
    return [question.hints.first, generic[1]];
  }

  static const List<String> _general = [
    'Read the question again slowly — what is it really asking for?',
    'Write down what you know, then think about which method connects it '
        'to what you need.',
  ];

  static const Map<PracticeTopic, List<String>> _byTopic = {
    PracticeTopic.algebra: [
      'Look at what is happening to the unknown — what operations are '
          'applied to it?',
      'Undo those operations one at a time, doing the same thing to both '
          'sides.',
    ],
    PracticeTopic.fractions: [
      'Check the denominators before anything else.',
      'Make the denominators match first, then work with the numerators.',
    ],
    PracticeTopic.geometry: [
      'Which geometric fact fits this shape — an angle sum, an area '
          'formula, or a theorem?',
      'Write the relevant formula or angle rule down, then substitute the '
          'given values.',
    ],
    PracticeTopic.trigonometry: [
      'Label the sides relative to the angle: opposite, adjacent, '
          'hypotenuse.',
      'Use SOH-CAH-TOA to choose the ratio that links the sides you know '
          'to the one you need.',
    ],
    PracticeTopic.calculus: [
      'Identify the form of the expression — which rule applies to it?',
      'Apply the rule term by term, keeping careful track of powers and '
          'coefficients.',
    ],
    PracticeTopic.statistics: [
      'Decide what the question measures: a centre (mean, median, mode) '
          'or a chance.',
      'Organize the data first — sort or count it — then apply the '
          'definition.',
    ],
    PracticeTopic.wordProblems: [
      'Underline the numbers and what the question asks for.',
      'Translate the words into a calculation or equation before '
          'computing anything.',
    ],
  };
}
