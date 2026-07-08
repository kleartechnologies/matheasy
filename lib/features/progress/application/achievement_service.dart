import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/achievement.dart';
import '../domain/achievement_catalog.dart';
import '../domain/achievement_progress.dart';

/// Evaluates the achievement catalog against a learner's metrics — the reusable
/// core of the framework.
///
/// Pure and swappable (mirrors the app's other `*Service` seams): a future
/// server-driven catalog implements the same interface via
/// [achievementServiceProvider] with no controller/UI change.
abstract interface class AchievementService {
  /// The full catalog paired with each achievement's progress + unlock date.
  List<AchievementView> evaluate(
    AchievementContext context,
    Map<AchievementId, DateTime> unlocks,
  );

  /// Achievements whose requirement is now met but which aren't yet unlocked.
  List<Achievement> pendingUnlocks(
    AchievementContext context,
    Map<AchievementId, DateTime> unlocks,
  );
}

/// Default metric-based evaluator over [Achievements.all].
class DefaultAchievementService implements AchievementService {
  const DefaultAchievementService();

  @override
  List<AchievementView> evaluate(
    AchievementContext context,
    Map<AchievementId, DateTime> unlocks,
  ) {
    return [
      for (final achievement in Achievements.all)
        AchievementView(
          achievement: achievement,
          progress: _progress(achievement, context),
          unlockedAt: unlocks[achievement.id],
        ),
    ];
  }

  @override
  List<Achievement> pendingUnlocks(
    AchievementContext context,
    Map<AchievementId, DateTime> unlocks,
  ) {
    return [
      for (final achievement in Achievements.all)
        if (!unlocks.containsKey(achievement.id) &&
            _progress(achievement, context).isComplete)
          achievement,
    ];
  }

  AchievementProgress _progress(
    Achievement achievement,
    AchievementContext context,
  ) {
    final target = achievement.requirement.target;
    final value = context.value(achievement.requirement.metric);
    return AchievementProgress(current: value.clamp(0, target), target: target);
  }
}

/// Provides the active [AchievementService].
final Provider<AchievementService> achievementServiceProvider =
    Provider<AchievementService>((ref) => const DefaultAchievementService());

/// The wall-clock, overridable in tests for deterministic unlock timestamps.
final Provider<DateTime Function()> clockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);
