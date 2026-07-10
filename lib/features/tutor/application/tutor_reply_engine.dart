import '../../result/domain/result_models.dart';
import '../domain/tutor_models.dart';

/// The deterministic, offline "brain" behind [MockTutorService].
///
/// Maps a student's message to an educational reply by detecting intent from
/// keywords, then composing warm, on-brand Matheasy copy plus optional inline cards
/// (quiz / practice) and follow-up suggestion chips. Pure and stateless — the
/// running [history] is passed in, so replies can vary (e.g. rotating examples)
/// while staying fully reproducible for tests.
///
/// ### Replacing with a real model
/// A real provider (OpenAI/Claude) returns the same [TutorResponse] shape, so
/// swapping [MockTutorService]'s engine changes nothing downstream. See
/// `tutor_service.dart` for the seam.
class TutorReplyEngine {
  const TutorReplyEngine();

  /// The opening turn when a chat starts. Scan-aware when [context] carries a
  /// recognized problem; otherwise a friendly, inviting welcome.
  TutorResponse greeting(TutorLaunchContext? context) {
    if (context != null && context.hasVisualStep) {
      return const TutorResponse(
        text: "I can see the exact step you're looking at 👀 — ask me "
            "anything about it, and we'll unpack why it works together.",
        suggestions: [
          SuggestionAction.tellMeWhy,
          SuggestionAction.explainSimpler,
          SuggestionAction.giveExample,
        ],
      );
    }
    if (context != null && context.hasScan) {
      final type = context.equationType ?? 'problem';
      final answer = context.answerLatex;
      final answerLine = answer == null
          ? ''
          : ' The answer works out to $answer, but the interesting part is '
              '*why*.';
      return TutorResponse(
        text: 'I can see your $type — nice work scanning it in! 🎯$answerLine '
            'What would you like to understand about it?',
        suggestions: const [
          SuggestionAction.tellMeWhy,
          SuggestionAction.explainSimpler,
          SuggestionAction.giveExample,
          SuggestionAction.createQuiz,
        ],
      );
    }
    return const TutorResponse(
      text: "Hi, I'm Matheasy — your personal math coach! 👋 Ask me anything, and "
          "we'll work through it together, step by step.",
      suggestions: [
        SuggestionAction.giveExample,
        SuggestionAction.createQuiz,
        SuggestionAction.practiceMore,
      ],
    );
  }

  /// Produce Matheasy's reply to [userText] given the running [history] and optional
  /// scan [context].
  TutorResponse reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
  }) {
    final text = userText.toLowerCase().trim();

    if (_matches(text, ['quiz', 'test me'])) return _quiz(history);
    if (_matches(text, ['practice', 'practise', 'exercise'])) {
      return _practice(history);
    }
    if (_matches(text, ['simpl', "like i'm", 'explain like', 'easier',
      'younger', 'eli5', 'dumb it down'])) {
      return _explainSimpler(context);
    }
    if (_matches(text, ['another way', 'other method', 'different method',
      'another method', 'other way'])) {
      return _anotherMethod();
    }
    if (_matches(text, ['example'])) return _example(history);
    if (_matches(text, ['why'])) return _why(context);
    if (_matches(text, ['exam', 'test prep', 'prepare'])) return _examPrep();
    if (_matches(text, ['algebra'])) return _algebra();
    if (_matches(text, ['fraction'])) return _fractions();
    if (_matches(text, ['geometr', 'triangle', 'angle'])) return _geometry();
    if (_matches(text, ['calculus', 'derivative', 'integral'])) return _calculus();
    if (_matches(text, ['trig', 'sine', 'cosine', 'tangent'])) {
      return _trigonometry();
    }
    if (_matches(text, ['statistic', 'mean', 'median', 'probability'])) {
      return _statistics();
    }
    if (_matches(text, ['word problem'])) return _wordProblems();
    if (_matches(text, ['thank', 'thx', 'appreciate'])) return _thanks();
    // Greetings use whole-word matching so 'hi'/'hey' don't fire inside words
    // like "this", "which" or "they".
    if (_hasWord(text, ['hi', 'hiya', 'hello', 'hey', 'yo', 'heya'])) {
      return _hello();
    }
    if (_matches(text, ['solve', 'help', 'stuck', "don't get", 'confused'])) {
      return _offerHelp(context);
    }
    return _fallback();
  }

  bool _matches(String text, List<String> keywords) =>
      keywords.any(text.contains);

  /// Whole-word match — splits [text] on non-letters and tests membership, so a
  /// short keyword can't accidentally match inside a longer word.
  bool _hasWord(String text, List<String> words) {
    final tokens = text.split(RegExp('[^a-z]+'));
    return words.any(tokens.contains);
  }

  /// Count prior user turns that contained any of [keywords] — used to rotate
  /// through a pool deterministically so repeated asks feel fresh.
  int _priorAsks(List<TutorMessage> history, List<String> keywords) {
    return history
        .where((m) => m.isUser && _matches(m.text.toLowerCase(), keywords))
        .length;
  }

  // ---- Intent responses ----

  TutorResponse _why(TutorLaunchContext? context) {
    return const TutorResponse(
      text: 'Great question — the *why* is the whole point! 🤔\n\n'
          'We subtract 5 first because we want x all by itself. The + 5 is '
          '"stuck" to x, and to remove it we use the opposite operation: '
          'subtraction. Whatever we do to one side, we do to the other, so the '
          'equation stays perfectly balanced.',
      suggestions: [
        SuggestionAction.explainSimpler,
        SuggestionAction.showAnotherMethod,
        SuggestionAction.giveExample,
        SuggestionAction.createQuiz,
      ],
    );
  }

  TutorResponse _explainSimpler(TutorLaunchContext? context) {
    return const TutorResponse(
      text: "Let's picture it! 🧱\n\n"
          'Imagine x is hiding behind a wall made of "+ 5". To see x, we take '
          'the wall away by doing "− 5". Now x is out in the open and we can '
          'read its value. Same idea every time: peel off whatever is stuck to '
          'x until x is alone.',
      suggestions: [
        SuggestionAction.giveExample,
        SuggestionAction.tellMeWhy,
        SuggestionAction.practiceMore,
      ],
    );
  }

  TutorResponse _example(List<TutorMessage> history) {
    const pool = <String>[
      r'3x + 6 = 18',
      r'4x - 2 = 10',
      r'5x + 3 = 23',
    ];
    final latex = pool[_priorAsks(history, ['example']) % pool.length];
    return TutorResponse(
      text: "Let's try one together. Can you solve it? I'll be right here if "
          'you get stuck. 👇',
      card: PracticeCard(
        PracticePrompt(
          questionLatex: latex,
          difficulty: Difficulty.easy,
          xpReward: 20,
          encouragement: 'Take it one step at a time — you can do this!',
        ),
      ),
      suggestions: const [
        SuggestionAction.tellMeWhy,
        SuggestionAction.explainSimpler,
        SuggestionAction.createQuiz,
      ],
    );
  }

  TutorResponse _quiz(List<TutorMessage> history) {
    const pool = <QuizQuestion>[
      QuizQuestion(
        prompt: 'Solve for x',
        promptLatex: r'2x + 4 = 10',
        options: [
          QuizOption(text: '2'),
          QuizOption(text: '3', isCorrect: true),
          QuizOption(text: '4'),
          QuizOption(text: '5'),
        ],
        explanation: 'Subtract 4 from both sides → 2x = 6, then divide by 2 → '
            'x = 3.',
      ),
      QuizQuestion(
        prompt: 'Solve for x',
        promptLatex: r'3x = 12',
        options: [
          QuizOption(text: '3'),
          QuizOption(text: '4', isCorrect: true),
          QuizOption(text: '5'),
          QuizOption(text: '6'),
        ],
        explanation: 'Divide both sides by 3 → x = 4. The 3 was multiplying x, '
            'so division undoes it.',
      ),
      QuizQuestion(
        prompt: 'Solve for x',
        promptLatex: r'x - 7 = 2',
        options: [
          QuizOption(text: '5'),
          QuizOption(text: '7'),
          QuizOption(text: '9', isCorrect: true),
          QuizOption(text: '14'),
        ],
        explanation: 'Add 7 to both sides → x = 9. Addition undoes the − 7.',
      ),
    ];
    final quiz = pool[_priorAsks(history, ['quiz', 'test me']) % pool.length];
    return TutorResponse(
      text: "Sure! Here's a quick quiz — take your time and tap your answer. "
          "There's no rush. 💪",
      card: QuizCard(quiz),
      suggestions: const [
        SuggestionAction.explainSimpler,
        SuggestionAction.giveExample,
        SuggestionAction.practiceMore,
      ],
    );
  }

  TutorResponse _practice(List<TutorMessage> history) {
    const pool = <PracticePrompt>[
      PracticePrompt(
        questionLatex: r'5x - 7 = 18',
        difficulty: Difficulty.medium,
        xpReward: 30,
        encouragement: "You've handled tougher — give it a go! 🌟",
      ),
      PracticePrompt(
        questionLatex: r'x + 9 = 15',
        difficulty: Difficulty.easy,
        xpReward: 15,
        encouragement: 'A nice warm-up. You’ve got this!',
      ),
      PracticePrompt(
        questionLatex: r'2(x + 3) = 16',
        difficulty: Difficulty.hard,
        xpReward: 45,
        encouragement: 'Expand the bracket first — then it’s just like before.',
      ),
    ];
    final prompt =
        pool[_priorAsks(history, ['practice', 'practise', 'exercise']) %
            pool.length];
    return TutorResponse(
      text: "Here's a practice question picked just for you. Solve it whenever "
          "you're ready — I'll check it with you.",
      card: PracticeCard(prompt),
      suggestions: const [
        SuggestionAction.tellMeWhy,
        SuggestionAction.giveExample,
        SuggestionAction.createQuiz,
      ],
    );
  }

  TutorResponse _anotherMethod() {
    return const TutorResponse(
      text: 'Absolutely — there’s usually more than one path! ✨\n\n'
          'Instead of the balance method, try *transposition*: move a term '
          'across the = sign and flip its sign. So 2x + 5 = 13 becomes '
          '2x = 13 − 5 = 8, then x = 8 ÷ 2 = 4. Same answer, fewer lines — handy '
          'under exam pressure.',
      suggestions: [
        SuggestionAction.explainSimpler,
        SuggestionAction.giveExample,
        SuggestionAction.practiceMore,
      ],
    );
  }

  TutorResponse _examPrep() {
    return const TutorResponse(
      text: "Let's get you exam-ready! 📝 The trick is steady practice on the "
          'question types that show up most. Want to warm up with a quick quiz, '
          'or a timed-style practice question?',
      suggestions: [
        SuggestionAction.createQuiz,
        SuggestionAction.practiceMore,
        SuggestionAction.giveExample,
      ],
    );
  }

  TutorResponse _algebra() => _topic(
        'Algebra is just arithmetic with a mystery number — usually x. Our job '
        'is to get x alone by undoing operations with their opposites. Add '
        '↔ subtract, multiply ↔ divide. Do the same to both sides and the '
        'balance holds. Want to see it in action?',
      );

  TutorResponse _fractions() => _topic(
        'Fractions are just parts of a whole. To add or subtract them, the '
        'bottom numbers (denominators) must match — then you work with the '
        'tops. To multiply, go straight across. Shall we try one?',
      );

  TutorResponse _geometry() => _topic(
        'Geometry is the math of shapes and space — angles, lengths and areas. '
        'A great anchor: the angles inside any triangle always add up to '
        '180°. Want a worked example?',
      );

  TutorResponse _calculus() => _topic(
        'Calculus studies change. Derivatives measure how fast something '
        'changes (a slope), and integrals add up tiny pieces (an area). We '
        'can start gentle — want a simple example?',
      );

  TutorResponse _trigonometry() => _topic(
        'Trigonometry links a triangle’s angles to its side lengths. The three '
        'stars are sine, cosine and tangent — remember SOH-CAH-TOA. Want me '
        'to break that down?',
      );

  TutorResponse _statistics() => _topic(
        'Statistics helps us make sense of data. The mean is the average, the '
        'median is the middle value, and the mode is the most common one. '
        'Want to practise with a small data set?',
      );

  TutorResponse _wordProblems() => _topic(
        'Word problems are stories hiding an equation. The skill is '
        'translation: pick the unknown, turn each sentence into math, then '
        'solve. Shall we translate one together?',
      );

  TutorResponse _topic(String body) {
    return TutorResponse(
      text: body,
      suggestions: const [
        SuggestionAction.giveExample,
        SuggestionAction.createQuiz,
        SuggestionAction.practiceMore,
      ],
    );
  }

  TutorResponse _offerHelp(TutorLaunchContext? context) {
    final about =
        context != null && context.hasScan ? ' with this problem' : '';
    return TutorResponse(
      text: "Of course — let's solve it together$about! 🙌 Tell me which step "
          'is tricky, or I can walk through it from the start. Where shall we '
          'begin?',
      suggestions: const [
        SuggestionAction.tellMeWhy,
        SuggestionAction.explainSimpler,
        SuggestionAction.giveExample,
      ],
    );
  }

  TutorResponse _hello() {
    return const TutorResponse(
      text: 'Hey there! 👋 Great to see you. What are we learning today?',
      suggestions: [
        SuggestionAction.giveExample,
        SuggestionAction.createQuiz,
        SuggestionAction.practiceMore,
      ],
    );
  }

  TutorResponse _thanks() {
    return const TutorResponse(
      text: "You're very welcome! 😊 You're doing really well — keep that "
          'curiosity going. Want to try another?',
      suggestions: [
        SuggestionAction.giveExample,
        SuggestionAction.practiceMore,
        SuggestionAction.createQuiz,
      ],
    );
  }

  TutorResponse _fallback() {
    return const TutorResponse(
      text: "Love that you're thinking about this! 💡 I can explain a concept, "
          'walk through an example, make a quiz, or set you a practice '
          'question. Which sounds good?',
      suggestions: [
        SuggestionAction.explainSimpler,
        SuggestionAction.giveExample,
        SuggestionAction.createQuiz,
        SuggestionAction.practiceMore,
      ],
    );
  }
}
