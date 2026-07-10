import 'package:flutter/foundation.dart';

import 'practice_difficulty.dart';
import 'practice_question.dart';
import 'practice_topic.dart';

/// A wrong answer, captured with everything Numi and the Visual Learning Engine
/// need to explain it: the question, the learner's answer, the correct answer,
/// the topic and the difficulty (exactly the fields the spec calls for).
@immutable
class PracticeMistake {
  const PracticeMistake({
    required this.question,
    required this.submittedAnswer,
  });

  final PracticeQuestion question;

  /// What the learner actually entered / selected.
  final String submittedAnswer;

  String get prompt => question.prompt;

  /// The problem as LaTeX when available (for Numi / Visual), else the plain
  /// prompt so there's always *something* to hand off.
  String get problemLatex => question.promptLatex ?? question.prompt;

  String get correctAnswer => question.correctAnswerText;

  PracticeTopic get topic => question.topic;

  PracticeDifficulty get difficulty => question.difficulty;

  /// A first-person message to seed a Numi "why is this wrong?" conversation.
  /// Carries the learner's answer + the correct answer inline, so Numi has the
  /// full picture even though only the problem latex travels as structured
  /// context on the wire.
  String get numiSeedMessage {
    final buffer = StringBuffer()
      ..write('I was practicing ${topic.label.toLowerCase()} and got this '
          'wrong:\n')
      ..write('"$prompt"');
    final latex = question.promptLatex;
    if (latex != null && latex.isNotEmpty) {
      buffer.write('  ($latex)');
    }
    buffer
      ..write('\nI answered "$submittedAnswer", but the correct answer is ')
      ..write('"$correctAnswer". Can you explain what I did wrong and how to '
          'get it right next time?');
    return buffer.toString();
  }
}
