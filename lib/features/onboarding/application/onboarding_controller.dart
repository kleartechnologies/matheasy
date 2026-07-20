import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/onboarding_models.dart';

part 'onboarding_controller.g.dart';

/// Holds the answers collected during the onboarding flow.
///
/// STAGE 2: in-memory only (no persistence, no Firebase). A later stage saves
/// [OnboardingData] and consumes it to personalize the app. This is distinct
/// from the session-level `OnboardingController` (a bool "completed" flag used
/// by the navigation guard).
@riverpod
class OnboardingFlowController extends _$OnboardingFlowController {
  @override
  OnboardingData build() => const OnboardingData();

  void selectLevel(StudyLevel level) => state = state.copyWith(level: level);

  void toggleTopic(MathTopic topic) {
    final next = {...state.topics};
    if (!next.add(topic)) next.remove(topic);
    state = state.copyWith(topics: next);
  }

  void selectGoal(DailyGoal goal) => state = state.copyWith(goal: goal);
}
