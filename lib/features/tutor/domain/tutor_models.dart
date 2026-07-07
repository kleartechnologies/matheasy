import 'package:flutter/material.dart';

import '../../../shared/mascot/numi_expression.dart';
import '../../result/domain/result_models.dart';

/// Who authored a chat message.
///
/// [system] messages are neutral, centered notices (e.g. "Numi can see your
/// scanned problem", "New conversation") — not part of the tutor's voice.
enum TutorRole { user, assistant, system }

/// A quick-reply chip the tutor offers under a response. Tapping one sends its
/// [message] back into the conversation as if the student had typed it — so the
/// same reply engine handles chips and free text identically.
enum SuggestionAction {
  explainSimpler(
    'Explain Simpler',
    Icons.wb_sunny_outlined,
    'Can you explain that more simply?',
  ),
  giveExample(
    'Give Example',
    Icons.lightbulb_outline_rounded,
    'Can you give me another example?',
  ),
  tellMeWhy(
    'Tell Me Why',
    Icons.help_outline_rounded,
    'But why does that work?',
  ),
  showAnotherMethod(
    'Show Another Method',
    Icons.alt_route_rounded,
    'Is there another method to solve this?',
  ),
  createQuiz(
    'Create Quiz',
    Icons.quiz_outlined,
    'Can you create a quiz for me?',
  ),
  practiceMore(
    'Practice More',
    Icons.fitness_center_rounded,
    'Give me a practice question.',
  );

  const SuggestionAction(this.label, this.icon, this.message);

  /// Chip label shown to the student.
  final String label;

  /// Leading chip icon.
  final IconData icon;

  /// The text sent to the tutor when the chip is tapped.
  final String message;
}

/// One option in a [QuizQuestion]. The card renders the A/B/C/D letter itself,
/// so [text] holds only the answer content.
@immutable
class QuizOption {
  const QuizOption({required this.text, this.isCorrect = false});

  final String text;
  final bool isCorrect;
}

/// A single multiple-choice quiz the tutor generates inline in the chat.
@immutable
class QuizQuestion {
  const QuizQuestion({
    required this.prompt,
    required this.options,
    required this.explanation,
    this.promptLatex,
  });

  /// Plain-language prompt, e.g. "Solve for x".
  final String prompt;

  /// Optional LaTeX equation shown large under the prompt (e.g. `2x + 4 = 10`).
  final String? promptLatex;

  final List<QuizOption> options;

  /// Shown after the student answers — the "why" behind the correct choice.
  final String explanation;

  int get correctIndex => options.indexWhere((o) => o.isCorrect);
}

/// A practice question the tutor suggests inline, with an encouraging nudge.
///
/// Reuses [Difficulty] from the result feature so difficulty reads consistently
/// across Scan → Result → Tutor.
@immutable
class PracticePrompt {
  const PracticePrompt({
    required this.questionLatex,
    required this.difficulty,
    required this.xpReward,
    required this.encouragement,
  });

  final String questionLatex;
  final Difficulty difficulty;
  final int xpReward;

  /// A short Numi line, e.g. "You've got this — take your time. 💪".
  final String encouragement;
}

/// An inline rich card attached to an assistant message. Sealed so the message
/// view can exhaustively switch, and so new card kinds (e.g. a diagram) slot in
/// without touching call sites.
@immutable
sealed class TutorCard {
  const TutorCard();
}

/// Wraps a [QuizQuestion] for rendering inside the chat.
final class QuizCard extends TutorCard {
  const QuizCard(this.question);
  final QuizQuestion question;
}

/// Wraps a [PracticePrompt] for rendering inside the chat.
final class PracticeCard extends TutorCard {
  const PracticeCard(this.prompt);
  final PracticePrompt prompt;
}

/// A single message in a tutor conversation.
///
/// A message is one "turn": text, an optional rich [card] (quiz/practice), and
/// the [suggestions] the tutor offers afterwards. [expression] drives the Numi
/// avatar mood for assistant turns.
@immutable
class TutorMessage {
  const TutorMessage({
    required this.id,
    required this.role,
    required this.text,
    this.card,
    this.suggestions = const [],
    this.expression = NumiExpression.happy,
  });

  /// Convenience for a user turn (plain text, no card/suggestions).
  const TutorMessage.user({required this.id, required this.text})
      : role = TutorRole.user,
        card = null,
        suggestions = const [],
        expression = NumiExpression.happy;

  /// Convenience for a neutral, centered system notice.
  const TutorMessage.system({required this.id, required this.text})
      : role = TutorRole.system,
        card = null,
        suggestions = const [],
        expression = NumiExpression.happy;

  final int id;
  final TutorRole role;
  final String text;
  final TutorCard? card;
  final List<SuggestionAction> suggestions;
  final NumiExpression expression;

  bool get isUser => role == TutorRole.user;
  bool get isAssistant => role == TutorRole.assistant;
  bool get isSystem => role == TutorRole.system;
}

/// The tutor's structured reply to a single user turn.
///
/// This is the shape the [TutorService] returns — the seam a real AI plugs into.
/// A future streaming provider yields the same fields incrementally without any
/// UI change.
@immutable
class TutorResponse {
  const TutorResponse({
    required this.text,
    this.card,
    this.suggestions = const [],
    this.expression = NumiExpression.happy,
  });

  final String text;
  final TutorCard? card;
  final List<SuggestionAction> suggestions;
  final NumiExpression expression;
}

/// Context handed to the chat when it opens.
///
/// Carries an optional [seedMessage] (from a tapped prompt/category — auto-sent
/// as the first user turn) and optional scanned-problem awareness so the chat
/// can open already knowing what the student is working on. All fields are mock
/// today; the shape is what a real session-context service would provide.
@immutable
class TutorLaunchContext {
  const TutorLaunchContext({
    this.seedMessage,
    this.questionLatex,
    this.answerLatex,
    this.equationType,
    this.topicLabel,
  });

  /// Auto-sent as the opening user message (from a suggested prompt/category).
  final String? seedMessage;

  /// The scanned problem, as LaTeX (e.g. `2x + 5 = 13`).
  final String? questionLatex;

  /// The scanned problem's answer, as LaTeX (e.g. `x = 4`).
  final String? answerLatex;

  /// Human label for the problem type, e.g. "Linear Equation".
  final String? equationType;

  /// Optional topic label used to steer explanations (e.g. "Algebra").
  final String? topicLabel;

  /// Whether the chat opened aware of a scanned problem.
  bool get hasScan => questionLatex != null;

  @override
  bool operator ==(Object other) =>
      other is TutorLaunchContext &&
      other.seedMessage == seedMessage &&
      other.questionLatex == questionLatex &&
      other.answerLatex == answerLatex &&
      other.equationType == equationType &&
      other.topicLabel == topicLabel;

  @override
  int get hashCode => Object.hash(
        seedMessage,
        questionLatex,
        answerLatex,
        equationType,
        topicLabel,
      );
}

/// Immutable snapshot of the live chat, exposed by the chat controller.
@immutable
class TutorSession {
  const TutorSession({
    this.messages = const [],
    this.isTyping = false,
    this.context,
  });

  final List<TutorMessage> messages;

  /// True while Numi is "thinking" — drives the typing indicator.
  final bool isTyping;

  /// The scan context this session was opened with, if any.
  final TutorLaunchContext? context;

  bool get isEmpty => messages.isEmpty;

  TutorSession copyWith({
    List<TutorMessage>? messages,
    bool? isTyping,
    TutorLaunchContext? context,
  }) {
    return TutorSession(
      messages: messages ?? this.messages,
      isTyping: isTyping ?? this.isTyping,
      context: context ?? this.context,
    );
  }
}

/// A suggested starter prompt shown on the Tutor home ("Explain Algebra", …).
@immutable
class TutorPrompt {
  const TutorPrompt({
    required this.label,
    required this.icon,
    required this.color,
    required this.message,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// The text used to seed the chat when tapped.
  final String message;
}

/// A learning category card on the Tutor home (Algebra, Geometry, …).
@immutable
class TutorCategory {
  const TutorCategory({
    required this.label,
    required this.icon,
    required this.color,
    required this.message,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String message;
}

/// One quick action on the Tutor home (Ask Numi, Upload Question, …).
@immutable
class TutorQuickAction {
  const TutorQuickAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.kind,
  });

  final String label;
  final IconData icon;
  final Color color;
  final TutorQuickActionKind kind;
}

/// The behavior a [TutorQuickAction] triggers. Kept as an enum (not a callback)
/// so the model stays pure and the screen owns navigation/side-effects.
enum TutorQuickActionKind { askNumi, uploadQuestion, practiceTopic, createQuiz }

/// A saved (mock) conversation shown under "Recent" on the Tutor home. Tapping
/// one loads its [messages] back into the chat.
@immutable
class TutorConversation {
  const TutorConversation({
    required this.id,
    required this.title,
    required this.preview,
    required this.icon,
    required this.messages,
  });

  final String id;
  final String title;

  /// A one-line snippet of the last exchange.
  final String preview;
  final IconData icon;

  /// The (mock) transcript restored when the conversation is reopened.
  final List<TutorMessage> messages;
}

/// All data the Tutor home renders. Supplied by a controller today from mock
/// content; a later stage swaps the source without touching the UI.
@immutable
class TutorHomeData {
  const TutorHomeData({
    required this.suggestedPrompts,
    required this.recentConversations,
    required this.categories,
    required this.quickActions,
  });

  final List<TutorPrompt> suggestedPrompts;
  final List<TutorConversation> recentConversations;
  final List<TutorCategory> categories;
  final List<TutorQuickAction> quickActions;
}
