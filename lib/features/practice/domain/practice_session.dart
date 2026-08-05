import 'package:flutter/foundation.dart';

import 'practice_difficulty.dart';
import 'practice_question.dart';
import 'practice_topic.dart';

/// A request to start a practice session. Also used as the `go_router` `extra`
/// payload when launching a session from Home / Result / Tutor.
@immutable
class PracticeRequest {
  const PracticeRequest({
    required this.topic,
    this.difficulty,
    this.questionCount = 5,
    this.isDailyChallenge = false,
    this.title,
    this.skillId,
    this.adaptive = false,
    this.practiceSetSourceKey,
  });

  /// The daily challenge: a fixed 5-question set with a bonus on completion.
  /// [adaptive] so the challenge scales with the learner's mastery (Pro).
  factory PracticeRequest.dailyChallenge() => const PracticeRequest(
        topic: PracticeTopic.algebra,
        isDailyChallenge: true,
        title: 'Daily Challenge',
        adaptive: true,
      );

  final PracticeTopic topic;

  /// A fixed difficulty, or `null` for a mixed / adaptively-chosen set.
  final PracticeDifficulty? difficulty;

  final int questionCount;
  final bool isDailyChallenge;

  /// Optional session title; falls back to the topic label.
  final String? title;

  /// Pin the whole session to one [PracticeSkill.id] — used for personalized
  /// reinforcement ("you just solved 2x+5=15, here's more like it"). `null`
  /// lets the engine pick skills within [topic].
  final String? skillId;

  /// Whether to select skills adaptively (weakness-weighted). Pro-only; the free
  /// tier always gets a basic ramp regardless of this flag.
  final bool adaptive;

  /// When this session is the MIXED REVIEW of a practice set (the journey
  /// generated from a solved problem), the set's source key — completing the
  /// session marks the set's mixed review done. Null for ordinary sessions.
  final String? practiceSetSourceKey;

  String get displayTitle => title ?? topic.label;

  /// Sentinel so [copyWith] can distinguish "not passed" from an explicit
  /// `difficulty: null` (which restores adaptive/mixed selection).
  static const Object _unset = Object();

  PracticeRequest copyWith({
    PracticeTopic? topic,
    Object? difficulty = _unset,
    int? questionCount,
    bool? isDailyChallenge,
    String? title,
    String? skillId,
    bool? adaptive,
    String? practiceSetSourceKey,
  }) {
    return PracticeRequest(
      topic: topic ?? this.topic,
      difficulty: identical(difficulty, _unset)
          ? this.difficulty
          : difficulty as PracticeDifficulty?,
      questionCount: questionCount ?? this.questionCount,
      isDailyChallenge: isDailyChallenge ?? this.isDailyChallenge,
      title: title ?? this.title,
      skillId: skillId ?? this.skillId,
      adaptive: adaptive ?? this.adaptive,
      practiceSetSourceKey: practiceSetSourceKey ?? this.practiceSetSourceKey,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PracticeRequest &&
      other.topic == topic &&
      other.difficulty == difficulty &&
      other.questionCount == questionCount &&
      other.isDailyChallenge == isDailyChallenge &&
      other.title == title &&
      other.skillId == skillId &&
      other.adaptive == adaptive &&
      other.practiceSetSourceKey == practiceSetSourceKey;

  @override
  int get hashCode => Object.hash(
        topic,
        difficulty,
        questionCount,
        isDailyChallenge,
        title,
        skillId,
        adaptive,
        practiceSetSourceKey,
      );
}

/// A recorded answer to one question — the FINAL outcome after any retries,
/// hints or solution views. Session-ephemeral: never serialized or synced.
@immutable
class PracticeAnswer {
  const PracticeAnswer({
    required this.questionId,
    required this.submitted,
    required this.isCorrect,
    required this.xpEarned,
    this.attempts = 1,
    this.hintLevelUsed = 0,
    this.viewedSolution = false,
    this.timeSpentSeconds = 0,
    this.workSteps,
  });

  final String questionId;
  final String submitted;
  final bool isCorrect;

  /// XP earned for this answer (0 if incorrect).
  final int xpEarned;

  /// Total submissions on this question (1 = correct/wrong first try).
  final int attempts;

  /// Highest hint level the student requested (0–4; 3+ came from the verified
  /// solve pipeline, 4 means the full guided solution was opened as a hint).
  final int hintLevelUsed;

  /// Whether the student opened the full solution before this answer was final.
  final bool viewedSolution;

  /// Wall-clock seconds from question shown to final answer.
  final int timeSpentSeconds;

  /// RESERVED — Compare My Work seam. A future feature will let the student
  /// type/upload their working; the steps land here and are checked
  /// deterministically server-side (functions/src/proxy/tutorWork.ts pattern)
  /// before any model sees them. Never populated today.
  final List<String>? workSteps;

  /// Whether any assistance (hint / retry / solution) preceded the answer —
  /// a first-try clean solve is the mastery signal.
  bool get isFirstTryClean =>
      attempts == 1 && hintLevelUsed == 0 && !viewedSolution;
}

/// The live progress on the CURRENT question before it resolves — attempts,
/// hint level, timing. Reset every time a new question is shown; folded into
/// the final [PracticeAnswer] on resolution.
@immutable
class QuestionAttempt {
  const QuestionAttempt({
    required this.startedAtMillis,
    this.attempts = 0,
    this.hintLevel = 0,
    this.viewedSolution = false,
    this.lastSubmitted,
  });

  /// When the question was shown (injected clock, not wall-clock reads inline).
  final int startedAtMillis;

  /// Submissions so far (incorrect ones included).
  final int attempts;

  /// Hint level requested so far (0 = none … 4 = full guided solution).
  final int hintLevel;

  final bool viewedSolution;

  /// The most recent incorrect submission (drives "Your answer: X" feedback).
  final String? lastSubmitted;

  QuestionAttempt copyWith({
    int? attempts,
    int? hintLevel,
    bool? viewedSolution,
    String? lastSubmitted,
  }) =>
      QuestionAttempt(
        startedAtMillis: startedAtMillis,
        attempts: attempts ?? this.attempts,
        hintLevel: hintLevel ?? this.hintLevel,
        viewedSolution: viewedSolution ?? this.viewedSolution,
        lastSubmitted: lastSubmitted ?? this.lastSubmitted,
      );
}

/// The live state of a practice session — the questions and answers so far.
@immutable
class PracticeSession {
  const PracticeSession({
    required this.request,
    required this.questions,
    this.currentIndex = 0,
    this.answers = const [],
  });

  final PracticeRequest request;
  final List<PracticeQuestion> questions;
  final int currentIndex;
  final List<PracticeAnswer> answers;

  PracticeTopic get topic => request.topic;
  PracticeQuestion get currentQuestion => questions[currentIndex];

  int get total => questions.length;
  int get answeredCount => answers.length;

  /// 1-based number of the current question.
  int get questionNumber => currentIndex + 1;

  /// Fraction of the session answered so far (drives the progress bar).
  double get progress => total == 0 ? 0 : (answeredCount / total).clamp(0.0, 1.0);

  int get correctCount => answers.where((a) => a.isCorrect).length;
  int get xpSoFar => answers.fold(0, (sum, a) => sum + a.xpEarned);

  bool get isLastQuestion => currentIndex >= total - 1;
  bool get isComplete => answeredCount >= total && total > 0;

  PracticeSession recordAnswer(PracticeAnswer answer) =>
      copyWith(answers: [...answers, answer]);

  PracticeSession advance() => copyWith(currentIndex: currentIndex + 1);

  /// Swaps a not-yet-reached question (mid-session difficulty adaptation).
  /// No-op when [index] is the current question or already answered.
  PracticeSession replaceUpcoming(int index, PracticeQuestion question) {
    if (index <= currentIndex || index >= questions.length) return this;
    final updated = [...questions]..[index] = question;
    return copyWith(questions: updated);
  }

  /// Inserts a question right after the current one ("Challenge Me").
  PracticeSession insertNext(PracticeQuestion question) {
    final updated = [...questions]..insert(currentIndex + 1, question);
    return copyWith(questions: updated);
  }

  PracticeSession copyWith({
    int? currentIndex,
    List<PracticeAnswer>? answers,
    List<PracticeQuestion>? questions,
  }) {
    return PracticeSession(
      request: request,
      questions: questions ?? this.questions,
      currentIndex: currentIndex ?? this.currentIndex,
      answers: answers ?? this.answers,
    );
  }
}
