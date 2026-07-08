import '../domain/practice_difficulty.dart';
import '../domain/practice_question.dart';
import '../domain/practice_topic.dart';

/// The offline, hand-authored question bank behind [MockPracticeService].
///
/// A real content service (authored questions or an AI generator) returns the
/// same [PracticeQuestion] shape, so swapping it changes nothing in the session
/// flow. Every topic spans all three difficulties; the four answer types are
/// mixed across the bank (algebra exercises all four, other topics use a subset).
class PracticeQuestionBank {
  const PracticeQuestionBank._();

  static List<PracticeQuestion> forTopic(PracticeTopic topic) =>
      _bank[topic] ?? _bank[PracticeTopic.algebra]!;

  static const Map<PracticeTopic, List<PracticeQuestion>> _bank = {
    PracticeTopic.algebra: _algebra,
    PracticeTopic.fractions: _fractions,
    PracticeTopic.geometry: _geometry,
    PracticeTopic.trigonometry: _trigonometry,
    PracticeTopic.calculus: _calculus,
    PracticeTopic.statistics: _statistics,
    PracticeTopic.wordProblems: _wordProblems,
  };

  static const List<PracticeQuestion> _algebra = [
    PracticeQuestion(
      id: 'alg-1',
      topic: PracticeTopic.algebra,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.equation,
      prompt: 'Solve for x',
      promptLatex: r'x + 4 = 9',
      acceptedAnswers: ['5', 'x=5'],
      explanation: 'Subtract 4 from both sides: x = 9 − 4 = 5.',
    ),
    PracticeQuestion(
      id: 'alg-2',
      topic: PracticeTopic.algebra,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Solve for x',
      promptLatex: r'2x + 4 = 10',
      options: [
        PracticeOption('2'),
        PracticeOption('3', isCorrect: true),
        PracticeOption('4'),
        PracticeOption('5'),
      ],
      explanation: 'Subtract 4 → 2x = 6, then divide by 2 → x = 3.',
    ),
    PracticeQuestion(
      id: 'alg-3',
      topic: PracticeTopic.algebra,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.equation,
      prompt: 'Solve for x',
      promptLatex: r'3x + 6 = 18',
      acceptedAnswers: ['4', 'x=4'],
      explanation: 'Subtract 6 → 3x = 12, then divide by 3 → x = 4.',
    ),
    PracticeQuestion(
      id: 'alg-4',
      topic: PracticeTopic.algebra,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.input,
      prompt: 'What is the value of 5x when x = 3?',
      acceptedAnswers: ['15'],
      explanation: '5 × 3 = 15.',
    ),
    PracticeQuestion(
      id: 'alg-5',
      topic: PracticeTopic.algebra,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.trueFalse,
      prompt: 'Is x = 5 a solution to 2x − 3 = 7?',
      options: [
        PracticeOption('True', isCorrect: true),
        PracticeOption('False'),
      ],
      explanation: '2(5) − 3 = 10 − 3 = 7 ✓, so yes.',
    ),
    PracticeQuestion(
      id: 'alg-6',
      topic: PracticeTopic.algebra,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.equation,
      prompt: 'Solve for x',
      promptLatex: r'5x - 7 = 18',
      acceptedAnswers: ['5', 'x=5'],
      explanation: 'Add 7 → 5x = 25, then divide by 5 → x = 5.',
    ),
  ];

  static const List<PracticeQuestion> _fractions = [
    PracticeQuestion(
      id: 'fr-1',
      topic: PracticeTopic.fractions,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.input,
      prompt: 'What is 1/2 + 1/2?',
      acceptedAnswers: ['1'],
      explanation: 'Same denominator: 1/2 + 1/2 = 2/2 = 1.',
    ),
    PracticeQuestion(
      id: 'fr-2',
      topic: PracticeTopic.fractions,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Add the fractions',
      promptLatex: r'\frac{1}{4} + \frac{1}{4}',
      spokenPrompt: 'one quarter plus one quarter',
      options: [
        PracticeOption('1/2', isCorrect: true),
        PracticeOption('2/8'),
        PracticeOption('1/4'),
        PracticeOption('1/8'),
      ],
      explanation: '1/4 + 1/4 = 2/4 = 1/2.',
    ),
    PracticeQuestion(
      id: 'fr-3',
      topic: PracticeTopic.fractions,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.trueFalse,
      prompt: 'Is 2/4 equal to 1/2?',
      options: [
        PracticeOption('True', isCorrect: true),
        PracticeOption('False'),
      ],
      explanation: 'Divide top and bottom by 2: 2/4 = 1/2 ✓.',
    ),
    PracticeQuestion(
      id: 'fr-4',
      topic: PracticeTopic.fractions,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Add the fractions',
      promptLatex: r'\frac{3}{4} + \frac{1}{2}',
      spokenPrompt: 'three quarters plus one half',
      options: [
        PracticeOption('5/4', isCorrect: true),
        PracticeOption('4/6'),
        PracticeOption('1'),
        PracticeOption('4/8'),
      ],
      explanation: '1/2 = 2/4, so 3/4 + 2/4 = 5/4.',
    ),
    PracticeQuestion(
      id: 'fr-5',
      topic: PracticeTopic.fractions,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.input,
      prompt: 'Simplify 6/8 to lowest terms',
      acceptedAnswers: ['3/4'],
      explanation: 'Divide top and bottom by 2: 6/8 = 3/4.',
    ),
    PracticeQuestion(
      id: 'fr-6',
      topic: PracticeTopic.fractions,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Subtract the fractions',
      promptLatex: r'\frac{5}{6} - \frac{1}{3}',
      spokenPrompt: 'five sixths minus one third',
      options: [
        PracticeOption('1/2', isCorrect: true),
        PracticeOption('4/3'),
        PracticeOption('4/6'),
        PracticeOption('1/6'),
      ],
      explanation: '1/3 = 2/6, so 5/6 − 2/6 = 3/6 = 1/2.',
    ),
  ];

  static const List<PracticeQuestion> _geometry = [
    PracticeQuestion(
      id: 'geo-1',
      topic: PracticeTopic.geometry,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.input,
      prompt: 'The angles in a triangle add up to how many degrees?',
      acceptedAnswers: ['180'],
      explanation: 'Every triangle’s interior angles sum to 180°.',
    ),
    PracticeQuestion(
      id: 'geo-2',
      topic: PracticeTopic.geometry,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'A right angle measures',
      options: [
        PracticeOption('45°'),
        PracticeOption('90°', isCorrect: true),
        PracticeOption('180°'),
        PracticeOption('360°'),
      ],
      explanation: 'A right angle is exactly 90°.',
    ),
    PracticeQuestion(
      id: 'geo-3',
      topic: PracticeTopic.geometry,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.input,
      prompt: 'A triangle has angles of 90° and 30°. What is the third angle?',
      acceptedAnswers: ['60'],
      explanation: '180 − 90 − 30 = 60°.',
    ),
    PracticeQuestion(
      id: 'geo-4',
      topic: PracticeTopic.geometry,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.trueFalse,
      prompt: 'A square has four equal sides.',
      options: [
        PracticeOption('True', isCorrect: true),
        PracticeOption('False'),
      ],
      explanation: 'By definition a square has four equal sides and angles.',
    ),
    PracticeQuestion(
      id: 'geo-5',
      topic: PracticeTopic.geometry,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.input,
      prompt: 'What is the area of a rectangle 5 by 4?',
      acceptedAnswers: ['20'],
      explanation: 'Area = length × width = 5 × 4 = 20.',
    ),
    PracticeQuestion(
      id: 'geo-6',
      topic: PracticeTopic.geometry,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'The perimeter of a square with side 6 is',
      options: [
        PracticeOption('12'),
        PracticeOption('24', isCorrect: true),
        PracticeOption('36'),
        PracticeOption('6'),
      ],
      explanation: 'Perimeter = 4 × side = 4 × 6 = 24.',
    ),
  ];

  static const List<PracticeQuestion> _trigonometry = [
    PracticeQuestion(
      id: 'trig-1',
      topic: PracticeTopic.trigonometry,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'SOH-CAH-TOA: sine = opposite ÷ ?',
      options: [
        PracticeOption('hypotenuse', isCorrect: true),
        PracticeOption('adjacent'),
        PracticeOption('opposite'),
        PracticeOption('angle'),
      ],
      explanation: 'SOH: Sine = Opposite / Hypotenuse.',
    ),
    PracticeQuestion(
      id: 'trig-2',
      topic: PracticeTopic.trigonometry,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.trueFalse,
      prompt: 'tan equals sin divided by cos.',
      options: [
        PracticeOption('True', isCorrect: true),
        PracticeOption('False'),
      ],
      explanation: 'tan θ = sin θ / cos θ.',
    ),
    PracticeQuestion(
      id: 'trig-3',
      topic: PracticeTopic.trigonometry,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.input,
      prompt: 'What is sin(30°) as a fraction?',
      acceptedAnswers: ['1/2'],
      explanation: 'sin(30°) = 1/2.',
    ),
    PracticeQuestion(
      id: 'trig-4',
      topic: PracticeTopic.trigonometry,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'cos(0°) equals',
      options: [
        PracticeOption('0'),
        PracticeOption('1', isCorrect: true),
        PracticeOption('-1'),
        PracticeOption('0.5'),
      ],
      explanation: 'cos(0°) = 1.',
    ),
    PracticeQuestion(
      id: 'trig-5',
      topic: PracticeTopic.trigonometry,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Right triangle: opposite = 3, hypotenuse = 5. sin = ?',
      options: [
        PracticeOption('3/5', isCorrect: true),
        PracticeOption('4/5'),
        PracticeOption('5/3'),
        PracticeOption('3/4'),
      ],
      explanation: 'sin = opposite / hypotenuse = 3/5.',
    ),
  ];

  static const List<PracticeQuestion> _calculus = [
    PracticeQuestion(
      id: 'calc-1',
      topic: PracticeTopic.calculus,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'A derivative measures the …',
      options: [
        PracticeOption('slope', isCorrect: true),
        PracticeOption('area'),
        PracticeOption('sum'),
        PracticeOption('average'),
      ],
      explanation: 'The derivative gives the instantaneous slope (rate of '
          'change).',
    ),
    PracticeQuestion(
      id: 'calc-2',
      topic: PracticeTopic.calculus,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.trueFalse,
      prompt: 'An integral can represent the area under a curve.',
      options: [
        PracticeOption('True', isCorrect: true),
        PracticeOption('False'),
      ],
      explanation: 'A definite integral is the signed area under a curve.',
    ),
    PracticeQuestion(
      id: 'calc-3',
      topic: PracticeTopic.calculus,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'The derivative of x² is',
      options: [
        PracticeOption('2x', isCorrect: true),
        PracticeOption('x'),
        PracticeOption('x²'),
        PracticeOption('2'),
      ],
      explanation: 'Power rule: d/dx xⁿ = n·xⁿ⁻¹, so d/dx x² = 2x.',
    ),
    PracticeQuestion(
      id: 'calc-4',
      topic: PracticeTopic.calculus,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.input,
      prompt: 'What is the derivative of 3x?',
      acceptedAnswers: ['3'],
      explanation: 'The derivative of a·x is a, so d/dx 3x = 3.',
    ),
    PracticeQuestion(
      id: 'calc-5',
      topic: PracticeTopic.calculus,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'The derivative of x³ is',
      options: [
        PracticeOption('3x²', isCorrect: true),
        PracticeOption('x²'),
        PracticeOption('3x'),
        PracticeOption('2x²'),
      ],
      explanation: 'Power rule: d/dx x³ = 3x².',
    ),
  ];

  static const List<PracticeQuestion> _statistics = [
    PracticeQuestion(
      id: 'stat-1',
      topic: PracticeTopic.statistics,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.input,
      prompt: 'What is the mean of 2, 4, and 6?',
      acceptedAnswers: ['4'],
      explanation: '(2 + 4 + 6) / 3 = 12 / 3 = 4.',
    ),
    PracticeQuestion(
      id: 'stat-2',
      topic: PracticeTopic.statistics,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'The middle value of a sorted list is the',
      options: [
        PracticeOption('median', isCorrect: true),
        PracticeOption('mean'),
        PracticeOption('mode'),
        PracticeOption('range'),
      ],
      explanation: 'The median is the middle value once the data is sorted.',
    ),
    PracticeQuestion(
      id: 'stat-3',
      topic: PracticeTopic.statistics,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.input,
      prompt: 'What is the median of 3, 5, and 9?',
      acceptedAnswers: ['5'],
      explanation: 'Sorted, the middle value of 3, 5, 9 is 5.',
    ),
    PracticeQuestion(
      id: 'stat-4',
      topic: PracticeTopic.statistics,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'The most frequent value is the',
      options: [
        PracticeOption('mode', isCorrect: true),
        PracticeOption('mean'),
        PracticeOption('median'),
        PracticeOption('range'),
      ],
      explanation: 'The mode is the value that appears most often.',
    ),
    PracticeQuestion(
      id: 'stat-5',
      topic: PracticeTopic.statistics,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.input,
      prompt: 'What is the mean of 10, 20, 30, and 40?',
      acceptedAnswers: ['25'],
      explanation: '(10 + 20 + 30 + 40) / 4 = 100 / 4 = 25.',
    ),
  ];

  static const List<PracticeQuestion> _wordProblems = [
    PracticeQuestion(
      id: 'word-1',
      topic: PracticeTopic.wordProblems,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'Sam has 3 apples and buys 2 more. How many apples now?',
      options: [
        PracticeOption('5', isCorrect: true),
        PracticeOption('6'),
        PracticeOption('1'),
        PracticeOption('23'),
      ],
      explanation: '3 + 2 = 5 apples.',
    ),
    PracticeQuestion(
      id: 'word-2',
      topic: PracticeTopic.wordProblems,
      difficulty: PracticeDifficulty.easy,
      type: PracticeQuestionType.input,
      prompt: 'A pack has 6 pens. How many pens are in 2 packs?',
      acceptedAnswers: ['12'],
      explanation: '6 × 2 = 12 pens.',
    ),
    PracticeQuestion(
      id: 'word-3',
      topic: PracticeTopic.wordProblems,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.input,
      prompt: 'Tickets cost \$4 each. What do 5 tickets cost, in dollars?',
      acceptedAnswers: ['20'],
      explanation: '4 × 5 = \$20.',
    ),
    PracticeQuestion(
      id: 'word-4',
      topic: PracticeTopic.wordProblems,
      difficulty: PracticeDifficulty.medium,
      type: PracticeQuestionType.multipleChoice,
      prompt: 'x + 3 = 10, where x is a number of apples. How many apples?',
      options: [
        PracticeOption('7', isCorrect: true),
        PracticeOption('13'),
        PracticeOption('3'),
        PracticeOption('10'),
      ],
      explanation: 'x = 10 − 3 = 7 apples.',
    ),
    PracticeQuestion(
      id: 'word-5',
      topic: PracticeTopic.wordProblems,
      difficulty: PracticeDifficulty.hard,
      type: PracticeQuestionType.input,
      prompt: 'A number doubled, plus 5, equals 17. What is the number?',
      acceptedAnswers: ['6'],
      explanation: '2x + 5 = 17 → 2x = 12 → x = 6.',
    ),
  ];
}
