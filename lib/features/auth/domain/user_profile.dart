import 'package:flutter/foundation.dart';

import '../../onboarding/domain/onboarding_models.dart';
import 'app_user.dart';

/// The user's profile — identity plus their (optional) learning preferences.
///
/// Stage 7 assembles this in-memory from the [AppUser] and the answers gathered
/// during onboarding; there is no editing UI yet and nothing is synced to the
/// cloud. A later stage persists/edits it, but the shape stays stable.
@immutable
class UserProfile {
  const UserProfile({
    required this.provider,
    required this.isGuest,
    this.displayName,
    this.email,
    this.photoUrl,
    this.gradeLevel,
    this.studyGoal,
    this.topics = const {},
  });

  /// Derives the profile from the signed-in [user] and their [onboarding]
  /// answers.
  factory UserProfile.from(AppUser user, OnboardingData onboarding) {
    return UserProfile(
      provider: user.provider,
      isGuest: user.isGuest,
      displayName: user.displayName,
      email: user.email,
      photoUrl: user.photoUrl,
      gradeLevel: onboarding.level,
      studyGoal: onboarding.goal,
      topics: onboarding.topics,
    );
  }

  final AuthProviderType provider;
  final bool isGuest;

  final String? displayName;
  final String? email;
  final String? photoUrl;

  /// Optional — from onboarding's study-level step.
  final StudyLevel? gradeLevel;

  /// Optional — from onboarding's daily-goal step.
  final DailyGoal? studyGoal;

  /// Optional — from onboarding's topic-selection step.
  final Set<MathTopic> topics;

  bool get hasLearningPreferences =>
      gradeLevel != null || studyGoal != null || topics.isNotEmpty;
}
