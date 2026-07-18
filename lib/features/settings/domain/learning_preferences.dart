import 'package:flutter/foundation.dart';

import '../../../core/localization/app_language.dart';
import '../../onboarding/domain/onboarding_models.dart';
import '../../practice/domain/practice_difficulty.dart';
import 'learning_goal.dart';

/// The learner's editable, locally-persisted study preferences.
///
/// Seeded from onboarding answers ([gradeLevel], [dailyGoal], [topics]) and
/// extended with a [learningGoal] and a practice [difficulty] preference. This
/// is the source of truth once the user edits their profile; nothing is synced
/// to the cloud in this stage.
@immutable
class LearningPreferences {
  const LearningPreferences({
    this.gradeLevel,
    this.learningGoal,
    this.dailyGoal,
    this.topics = const <MathTopic>{},
    this.difficulty = PracticeDifficulty.medium,
    this.language = AppLanguage.english,
  });

  static const LearningPreferences defaults = LearningPreferences();

  /// From onboarding's study-level step.
  final StudyLevel? gradeLevel;

  /// Why the learner is studying (new in Stage 10).
  final LearningGoal? learningGoal;

  /// From onboarding's daily-goal step.
  final DailyGoal? dailyGoal;

  /// Topics the learner wants to focus on.
  final Set<MathTopic> topics;

  /// Preferred practice difficulty — the engine level the learner picks; the
  /// authority for practice generation (defaults to [PracticeDifficulty.medium]).
  final PracticeDifficulty difficulty;

  /// The learner's language — controls the whole learning experience (UI + every
  /// AI response). Math notation stays universal. Defaults to [AppLanguage.english].
  final AppLanguage language;

  /// Whether the learner has set any preference beyond the defaults.
  bool get isConfigured =>
      gradeLevel != null ||
      learningGoal != null ||
      dailyGoal != null ||
      topics.isNotEmpty;

  LearningPreferences copyWith({
    StudyLevel? gradeLevel,
    LearningGoal? learningGoal,
    DailyGoal? dailyGoal,
    Set<MathTopic>? topics,
    PracticeDifficulty? difficulty,
    AppLanguage? language,
  }) {
    return LearningPreferences(
      gradeLevel: gradeLevel ?? this.gradeLevel,
      learningGoal: learningGoal ?? this.learningGoal,
      dailyGoal: dailyGoal ?? this.dailyGoal,
      topics: topics ?? this.topics,
      difficulty: difficulty ?? this.difficulty,
      language: language ?? this.language,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LearningPreferences &&
      other.gradeLevel == gradeLevel &&
      other.learningGoal == learningGoal &&
      other.dailyGoal == dailyGoal &&
      setEquals(other.topics, topics) &&
      other.difficulty == difficulty &&
      other.language == language;

  @override
  int get hashCode => Object.hash(
        gradeLevel,
        learningGoal,
        dailyGoal,
        Object.hashAllUnordered(topics),
        difficulty,
        language,
      );
}
