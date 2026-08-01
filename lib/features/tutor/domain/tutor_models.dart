import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/theme/math_semantics.dart';
import '../../result/domain/result_models.dart';
import '../../result/domain/visual_models.dart';

/// Who authored a chat message.
///
/// [system] messages are neutral, centered notices (e.g. "Numi can see your
/// scanned problem", "New conversation") — not part of the tutor's voice.
enum TutorRole { user, assistant, system }

/// How the student asked Numi to teach them (spec Part 3).
///
/// A mode is a behavioural contract, not a tone: [hint] may not reveal the
/// answer even when asked, [solveTogether] and [quizMe] must stop and wait for
/// the student. The server enforces each contract — and for the modes where
/// [revealsAnswer] is false it withholds the verified answer from the model
/// entirely, so the rule can't be talked around.
enum TutorMode {
  hint('hint', '👀', Icons.lightbulb_outline_rounded),
  solveTogether('solveTogether', '🤝', Icons.handshake_outlined),
  teachMe('teachMe', '📖', Icons.menu_book_rounded),
  showSolution('showSolution', '✅', Icons.checklist_rtl_rounded),
  quizMe('quizMe', '📝', Icons.quiz_outlined);

  const TutorMode(this.id, this.emoji, this.icon);

  /// Wire id shared with the `tutorReply` Cloud Function.
  final String id;

  /// The mode's glyph in the picker, per the spec's menu.
  final String emoji;

  final IconData icon;

  /// The mode a student lands in when they haven't chosen — the one that
  /// teaches, rather than the one that answers.
  static const TutorMode fallback = TutorMode.solveTogether;

  static TutorMode fromId(String? id) {
    for (final mode in values) {
      if (mode.id == id) return mode;
    }
    return fallback;
  }

  /// Whether this mode is allowed to state the final answer.
  bool get revealsAnswer =>
      this == teachMe || this == showSolution || this == solveTogether;
}

/// A quick-reply chip Numi offers under a response.
///
/// Tapping one sends its (localized) text back into the conversation as if the
/// student had typed it, so chips and free text take the identical path. Labels
/// and messages live in l10n — see `TutorCopy` — because this enum is also the
/// wire vocabulary the server picks from, and ids must not change per language.
enum SuggestionAction {
  explainSimpler('explainSimpler', Icons.wb_sunny_outlined),
  giveExample('giveExample', Icons.lightbulb_outline_rounded),
  tellMeWhy('tellMeWhy', Icons.help_outline_rounded),
  showAnotherMethod('showAnotherMethod', Icons.alt_route_rounded),
  createQuiz('createQuiz', Icons.quiz_outlined),
  practiceMore('practiceMore', Icons.fitness_center_rounded),
  giveHint('giveHint', Icons.visibility_outlined),
  nextStep('nextStep', Icons.skip_next_rounded),
  checkMyWork('checkMyWork', Icons.fact_check_outlined),
  commonMistakes('commonMistakes', Icons.warning_amber_rounded),
  practiceEasier('practiceEasier', Icons.trending_down_rounded),
  practiceSimilar('practiceSimilar', Icons.repeat_rounded),
  practiceHarder('practiceHarder', Icons.trending_up_rounded),
  practiceChallenge('practiceChallenge', Icons.local_fire_department_outlined),
  showSolution('showSolution', Icons.checklist_rtl_rounded),
  iDontUnderstand('iDontUnderstand', Icons.psychology_alt_outlined);

  const SuggestionAction(this.id, this.icon);

  /// Wire id shared with the `tutorReply` Cloud Function.
  final String id;

  /// Leading chip icon.
  final IconData icon;

  static SuggestionAction? fromId(String? id) {
    for (final action in values) {
      if (action.id == id) return action;
    }
    return null;
  }

  /// The mode this chip switches the conversation into, if any.
  ///
  /// Only the "show me the solution" escape hatch switches mode: a student in
  /// Hint mode who gives up must be able to leave in one tap, without hunting
  /// for the mode switcher.
  TutorMode? get switchesTo =>
      this == SuggestionAction.showSolution ? TutorMode.showSolution : null;
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

/// The equation Numi is pointing at this turn, with only the part she is
/// talking about lit up (spec Parts 7–8).
///
/// [latex] is never the model's own writing: the server replaces it with the
/// app's verified copy — the problem, the step on screen, or a verified step
/// result — or drops the focus entirely. So a highlight can only ever draw
/// attention *within* maths the app already stands behind.
@immutable
class TutorFocus {
  const TutorFocus({
    required this.latex,
    required this.caption,
    this.highlights = const [],
    this.sketch,
  });

  /// The equation, exactly as the app verified it.
  final String latex;

  /// One short line naming what is highlighted, in the student's language.
  final String caption;

  /// The pieces to colour — each a literal substring of [latex].
  final List<MathHighlight> highlights;

  /// An optional drawing of the same maths (spec Part 9) — a fraction bar, a
  /// number line, a curve with its roots, a shaded integral.
  ///
  /// Its numbers are derived server-side from [latex], never proposed by the
  /// model, so the picture and the equation can't disagree.
  final VisualConcept? sketch;

  /// The role that names what this focus is *about* — the caption wears its
  /// colour, so the vocabulary is legible without a legend.
  MathRole get leadRole =>
      highlights.isEmpty ? MathRole.aside : highlights.first.role;
}

/// A single message in a tutor conversation.
///
/// A message is one "turn": text, an optional photo the student sent, an
/// optional rich [card] (quiz/practice), an optional [focus] equation, and the
/// [suggestions] the tutor offers afterwards.
@immutable
class TutorMessage {
  const TutorMessage({
    required this.id,
    required this.role,
    required this.text,
    this.card,
    this.focus,
    this.suggestions = const [],
    this.image,
  });

  /// Convenience for a user turn (text and/or a photo, no card/suggestions).
  const TutorMessage.user({
    required this.id,
    required this.text,
    this.image,
  })  : role = TutorRole.user,
        card = null,
        focus = null,
        suggestions = const [];

  /// Convenience for a neutral, centered system notice.
  const TutorMessage.system({required this.id, required this.text})
      : role = TutorRole.system,
        card = null,
        focus = null,
        suggestions = const [],
        image = null;

  final int id;
  final TutorRole role;
  final String text;
  final TutorCard? card;

  /// The equation this turn is pointing at, if it is about a specific piece of
  /// one (spec Part 8).
  final TutorFocus? focus;
  final List<SuggestionAction> suggestions;

  /// The photo the student attached to this turn, as JPEG bytes.
  ///
  /// Transient and in-memory only, for the same reason as
  /// `DetectedEquation.imageBytes`: it is what the student is looking at right
  /// now, not state worth persisting — and a child's photo of their homework is
  /// the last thing that should end up in a sync blob.
  final Uint8List? image;

  bool get isUser => role == TutorRole.user;
  bool get isAssistant => role == TutorRole.assistant;
  bool get isSystem => role == TutorRole.system;

  bool get hasImage => image != null;
}

/// What a photo the student sent Numi turned out to be (spec Part 2).
///
/// [notMath] and [unreadable] are ordinary, successful outcomes — the student
/// gets a real, specific reply either way. "Never silently fail" means the
/// honest branches are first-class, not error handling.
enum TutorImageKind {
  /// A question the student wants help with.
  problem('problem'),

  /// The student's own working, for critique (spec Part 12).
  work('work'),

  /// A readable photo with no mathematics in it.
  notMath('notMath'),

  /// There may be math, but it couldn't be made out.
  unreadable('unreadable');

  const TutorImageKind(this.id);

  /// Wire id shared with the `tutorImage` Cloud Function.
  final String id;

  /// Unknown ids degrade to [unreadable] — the honest branch — never a guess.
  static TutorImageKind fromId(String? id) {
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return TutorImageKind.unreadable;
  }

  /// Whether anything was transcribed that the app can work with.
  bool get isReadable => this == problem || this == work;
}

/// A transcription-only read of a photo the student sent in chat.
///
/// Deliberately carries no answer and no judgement: `tutorImage` reads, the
/// app's own deterministic solver solves, and the server's work-checker decides
/// whether a line is right. This is only what was on the paper.
@immutable
class TutorImageRead {
  const TutorImageRead({
    required this.kind,
    this.problem = '',
    this.work = const [],
    this.note = '',
    this.confidence = 0,
  });

  /// The honest fallback used when the backend can't be reached at all.
  static const TutorImageRead unreadable =
      TutorImageRead(kind: TutorImageKind.unreadable);

  final TutorImageKind kind;

  /// The ORIGINAL question, as LaTeX. Empty when the photo showed only working.
  final String problem;

  /// The student's own working, one transcribed line per written line.
  final List<String> work;

  /// A short note from the read, in the learner's language — e.g. "the last two
  /// lines are cut off". Shown to the student as-is; never a verdict.
  final String note;

  /// How clearly the photo could be read, 0–1.
  final double confidence;

  bool get hasProblem => problem.trim().isNotEmpty;
  bool get hasWork => work.isNotEmpty;
}

/// The localized lines the photo flow speaks, resolved by the screen and handed
/// to the controller.
///
/// Same pattern as the suggestion chips: the controller owns the orchestration,
/// the widget layer owns the words. Without this a student reading Malay would
/// see themselves say "Can you check my working?" in English.
@immutable
class TutorImageCopy {
  const TutorImageCopy({
    required this.askProblem,
    required this.askWork,
    required this.sawProblem,
    required this.sawWork,
    required this.notMath,
    required this.unreadable,
    required this.failed,
  });

  /// Posted as the student's turn when they send a photo of a question.
  final String askProblem;

  /// Posted as the student's turn when they send a photo of their working.
  final String askWork;

  /// System notice: the problem was read out of the photo.
  final String sawProblem;

  /// System notice: the student's working was read out of the photo.
  final String sawWork;

  /// Numi's reply when the photo held no mathematics.
  final String notMath;

  /// Numi's reply when the photo couldn't be made out.
  final String unreadable;

  /// Numi's reply when the read itself failed (offline, quota, backend error).
  final String failed;
}

/// How well the student is tracking, as read from the last turn.
enum TutorUnderstanding { struggling, following, confident }

/// The register a student learns best in (spec Part 11).
enum TutorStyle { concise, detailed, visual }

/// The learning signals Numi reports alongside a reply.
///
/// These are what make adaptation *state* rather than something the model has
/// to re-infer from tone every turn: the client folds them into [TutorMemory]
/// and sends the accumulated picture back on the next request.
@immutable
class TutorTurnMeta {
  const TutorTurnMeta({
    this.conceptsCovered = const [],
    this.mistake,
    this.understanding = TutorUnderstanding.following,
    this.checkpoint = false,
    this.style,
  });

  /// Short names of the ideas taught this turn ("balance method").
  final List<String> conceptsCovered;

  /// The specific misconception the student just showed, if any.
  final String? mistake;

  final TutorUnderstanding understanding;

  /// True when the reply ends on a question the student must answer.
  final bool checkpoint;

  final TutorStyle? style;
}

/// What Numi has learned about this student during the conversation
/// (spec Parts 10, 11, 13).
///
/// Deliberately session-scoped and in-memory: it steers the next few turns, and
/// nothing here is worth persisting about a child across sessions.
@immutable
class TutorMemory {
  const TutorMemory({
    this.conceptsCovered = const [],
    this.mistakes = const [],
    this.strengths = const [],
    this.style,
    this.struggleStreak = 0,
  });

  /// Concepts already explained — Numi builds on these instead of repeating.
  final List<String> conceptsCovered;

  /// Misconceptions seen this session.
  final List<String> mistakes;

  /// Ideas the student has demonstrated they hold.
  final List<String> strengths;

  final TutorStyle? style;

  /// Consecutive turns the student has read as struggling.
  final int struggleStreak;

  /// How much more help the next turn should carry (spec Part 4). Capped at 3,
  /// where Numi stops asking the student to produce the step and shows it.
  int get helpLevel => struggleStreak > 3 ? 3 : struggleStreak;

  bool get isEmpty =>
      conceptsCovered.isEmpty &&
      mistakes.isEmpty &&
      strengths.isEmpty &&
      style == null;

  /// Fold one turn's signals in, oldest entries dropping out first.
  ///
  /// A `confident` turn resets the struggle streak — recovery should un-escalate
  /// the help level, or a student who stumbles once gets talked down to for the
  /// rest of the conversation.
  TutorMemory fold(TutorTurnMeta meta) {
    const cap = 12;
    final concepts = [
      ...conceptsCovered,
      for (final c in meta.conceptsCovered)
        if (!conceptsCovered.contains(c)) c,
    ];
    final mistake = meta.mistake;
    final nextMistakes = [
      ...mistakes,
      if (mistake != null && !mistakes.contains(mistake)) mistake,
    ];
    // A concept the student got right after being taught it is a strength.
    final nextStrengths = meta.understanding == TutorUnderstanding.confident
        ? [
            ...strengths,
            for (final c in meta.conceptsCovered)
              if (!strengths.contains(c)) c,
          ]
        : strengths;

    return TutorMemory(
      conceptsCovered: _tail(concepts, cap),
      mistakes: _tail(nextMistakes, 6),
      strengths: _tail(nextStrengths, 6),
      style: meta.style ?? style,
      struggleStreak: switch (meta.understanding) {
        TutorUnderstanding.struggling => struggleStreak + 1,
        TutorUnderstanding.following => struggleStreak,
        TutorUnderstanding.confident => 0,
      },
    );
  }

  /// Register a struggle signal the student sent directly (tapping "I don't
  /// understand"), without waiting for the model to notice it.
  TutorMemory struggling() => TutorMemory(
        conceptsCovered: conceptsCovered,
        mistakes: mistakes,
        strengths: strengths,
        style: style,
        struggleStreak: struggleStreak + 1,
      );

  static List<String> _tail(List<String> items, int cap) =>
      items.length <= cap ? items : items.sublist(items.length - cap);
}

/// One verified solution step, as Numi needs to see it.
@immutable
class TutorContextStep {
  const TutorContextStep({
    required this.title,
    required this.resultLatex,
    this.detail = '',
    this.rule,
  });

  final String title;
  final String resultLatex;
  final String detail;
  final String? rule;
}

/// The full solve context handed to Numi (spec Part 1).
///
/// Everything the app already knows about the problem on screen, so Numi never
/// has to ask "which equation do you mean?". Assembled by `TutorContextBuilder`
/// from the verified result — no new solving, no new LLM call.
@immutable
class TutorProblemContext {
  const TutorProblemContext({
    required this.questionLatex,
    this.questionText,
    this.problemType,
    this.topic,
    this.difficulty,
    this.finalAnswer,
    this.verified = false,
    this.verifyText,
    this.steps = const [],
    this.commonMistakes = const [],
    this.source,
  });

  final String questionLatex;

  /// The problem as the student sees it (OCR text / typed input).
  final String? questionText;

  final String? problemType;
  final String? topic;
  final String? difficulty;

  /// The final answer. Authoritative only when [verified].
  final String? finalAnswer;

  /// Whether the answer passed the app's substitution gate.
  final bool verified;

  /// How the answer was checked, in one sentence.
  final String? verifyText;

  final List<TutorContextStep> steps;

  /// Traps students hit on this kind of problem (spec Part 13).
  final List<String> commonMistakes;

  /// Where the problem came from: scan, typed, practice.
  final String? source;
}

/// The exact step the student tapped "Ask Numi about this step" on (spec Part 6).
@immutable
class TutorStepFocus {
  const TutorStepFocus({
    required this.summary,
    this.index,
    this.total,
    this.equationLatex,
  });

  /// One plain-text sentence describing the step, built by `VisualPromptBuilder`.
  final String summary;

  final int? index;
  final int? total;

  /// The expression on screen at this step.
  final String? equationLatex;
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
    this.focus,
    this.suggestions = const [],
    this.meta = const TutorTurnMeta(),
  });

  final String text;
  final TutorCard? card;

  /// The equation to highlight alongside this reply (spec Part 8).
  final TutorFocus? focus;
  final List<SuggestionAction> suggestions;

  /// Learning signals folded into the session's [TutorMemory].
  final TutorTurnMeta meta;
}

/// Context handed to the chat when it opens.
///
/// Carries an optional [seedMessage] (from a tapped prompt/category — auto-sent
/// as the first user turn) plus problem awareness, so the chat opens already
/// knowing what the student is working on.
///
/// The scalar fields ([questionLatex], [answerLatex], …) are the minimum a
/// caller can supply; [problem] is the full verified picture and takes
/// precedence when present. Both are exposed through the same getters so call
/// sites read one shape either way.
@immutable
class TutorLaunchContext {
  const TutorLaunchContext({
    this.seedMessage,
    this.mode,
    this.problem,
    this.stepFocus,
    String? questionLatex,
    String? answerLatex,
    String? equationType,
    String? topicLabel,
    String? visualStepSummary,
  })  : _questionLatex = questionLatex,
        _answerLatex = answerLatex,
        _equationType = equationType,
        _topicLabel = topicLabel,
        _visualStepSummary = visualStepSummary;

  /// Auto-sent as the opening user message (from a suggested prompt/category).
  final String? seedMessage;

  /// The mode to open in. Null means "ask the student" — the picker shows.
  final TutorMode? mode;

  /// The full verified solve context (spec Part 1), when the caller has one.
  final TutorProblemContext? problem;

  /// The exact step the student tapped, when they came from a step (Part 6).
  final TutorStepFocus? stepFocus;

  final String? _questionLatex;
  final String? _answerLatex;
  final String? _equationType;
  final String? _topicLabel;
  final String? _visualStepSummary;

  /// The problem, as LaTeX (e.g. `2x + 5 = 13`).
  String? get questionLatex => problem?.questionLatex ?? _questionLatex;

  /// The problem's answer, as LaTeX (e.g. `x = 4`).
  String? get answerLatex => problem?.finalAnswer ?? _answerLatex;

  /// Human label for the problem type, e.g. "Linear Equation".
  String? get equationType => problem?.problemType ?? _equationType;

  /// Topic label used to steer explanations (e.g. "Algebra").
  String? get topicLabel => problem?.topic ?? _topicLabel;

  /// The step the student tapped, as one plain-text sentence — lets Numi answer
  /// "why divide by 2?" about the exact step on screen.
  String? get visualStepSummary => stepFocus?.summary ?? _visualStepSummary;

  /// Whether the chat opened aware of a problem.
  bool get hasScan => questionLatex != null;

  /// Whether the chat opened from a Visual Learning step.
  bool get hasVisualStep => visualStepSummary != null;

  /// Whether the student should be asked how they want to learn this. Only
  /// worth asking when there's a problem to learn *about*.
  bool get needsModeChoice => mode == null && hasScan;

  @override
  bool operator ==(Object other) =>
      other is TutorLaunchContext &&
      other.seedMessage == seedMessage &&
      other.mode == mode &&
      other.questionLatex == questionLatex &&
      other.answerLatex == answerLatex &&
      other.equationType == equationType &&
      other.topicLabel == topicLabel &&
      other.visualStepSummary == visualStepSummary;

  @override
  int get hashCode => Object.hash(
        seedMessage,
        mode,
        questionLatex,
        answerLatex,
        equationType,
        topicLabel,
        visualStepSummary,
      );
}

/// Immutable snapshot of the live chat, exposed by the chat controller.
@immutable
class TutorSession {
  const TutorSession({
    this.messages = const [],
    this.isTyping = false,
    this.streamingId,
    this.context,
    this.mode = TutorMode.fallback,
    this.memory = const TutorMemory(),
    this.awaitingModeChoice = false,
  });

  final List<TutorMessage> messages;

  /// True for as long as Numi is answering — thinking *or* mid-sentence. Holds
  /// the composer closed so a second question can't interleave with the turn in
  /// flight.
  final bool isTyping;

  /// The message Numi's reply is currently being written into, once the first
  /// words have arrived (spec Part 18); null while she is still thinking.
  ///
  /// The typing indicator gives way to it: there is no sense showing three dots
  /// under a sentence that is already appearing.
  final int? streamingId;

  /// True while Numi is thinking and has nothing on screen yet — the moment the
  /// typing indicator is for.
  bool get isThinking => isTyping && streamingId == null;

  /// The problem context this session was opened with, if any.
  final TutorLaunchContext? context;

  /// How the student asked to learn (spec Part 3).
  final TutorMode mode;

  /// What Numi has learned about this student this session.
  final TutorMemory memory;

  /// True while the "How would you like to learn this?" picker is up and the
  /// student hasn't chosen yet.
  final bool awaitingModeChoice;

  bool get isEmpty => messages.isEmpty;

  /// [clearStreaming] ends the streaming turn — needed because passing null for
  /// [streamingId] means "unchanged", as it does for every other field here.
  TutorSession copyWith({
    List<TutorMessage>? messages,
    bool? isTyping,
    int? streamingId,
    bool clearStreaming = false,
    TutorLaunchContext? context,
    TutorMode? mode,
    TutorMemory? memory,
    bool? awaitingModeChoice,
  }) {
    return TutorSession(
      messages: messages ?? this.messages,
      isTyping: isTyping ?? this.isTyping,
      streamingId: clearStreaming ? null : (streamingId ?? this.streamingId),
      context: context ?? this.context,
      mode: mode ?? this.mode,
      memory: memory ?? this.memory,
      awaitingModeChoice: awaitingModeChoice ?? this.awaitingModeChoice,
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
enum TutorQuickActionKind { askMatheasy, uploadQuestion, practiceTopic, createQuiz }

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
