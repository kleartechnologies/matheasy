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

  PracticeRequest copyWith({
    PracticeTopic? topic,
    PracticeDifficulty? difficulty,
    int? questionCount,
    bool? isDailyChallenge,
    String? title,
    String? skillId,
    bool? adaptive,
    String? practiceSetSourceKey,
  }) {
    return PracticeRequest(
      topic: topic ?? this.topic,
      difficulty: difficulty ?? this.difficulty,
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

/// A recorded answer to one question.
@immutable
class PracticeAnswer {
  const PracticeAnswer({
    required this.questionId,
    required this.submitted,
    required this.isCorrect,
    required this.xpEarned,
  });

  final String questionId;
  final String submitted;
  final bool isCorrect;

  /// XP earned for this answer (0 if incorrect).
  final int xpEarned;
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

  PracticeSession copyWith({
    int? currentIndex,
    List<PracticeAnswer>? answers,
  }) {
    return PracticeSession(
      request: request,
      questions: questions,
      currentIndex: currentIndex ?? this.currentIndex,
      answers: answers ?? this.answers,
    );
  }
}
