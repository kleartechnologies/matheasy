import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/progress_stats.dart';
import 'achievement_service.dart' show clockProvider;
import 'progress_stats_repository.dart';

part 'stats_controller.g.dart';

/// The local analytics store — records scans, tutor usage, learning days and the
/// recent-activity feed. Kept alive; hydrates on build and persists on change.
///
/// This is the single mutator of [ProgressStats]; the achievement engine and
/// progress dashboard read from it.
@Riverpod(keepAlive: true)
class StatsController extends _$StatsController {
  @override
  ProgressStats build() => ref.read(progressStatsRepositoryProvider).load();

  /// Records that the learner scanned a problem.
  void recordScan() {
    final now = ref.read(clockProvider)();
    _apply(
      scans: state.scans + 1,
      day: _epochDay(now),
      activity: LearningActivity(
        type: LearningActivityType.scan,
        title: 'Scanned a problem',
        subtitle: 'Snapped a question to solve',
        epochMillis: now.millisecondsSinceEpoch,
      ),
    );
  }

  /// Records that the learner used Matheasy (the AI tutor). Only the first use
  /// adds a feed entry, so the activity list isn't spammed.
  void recordTutorUsed() {
    final now = ref.read(clockProvider)();
    _apply(
      tutorUses: state.tutorUses + 1,
      day: _epochDay(now),
      activity: state.tutorUses == 0
          ? LearningActivity(
              type: LearningActivityType.tutor,
              title: 'Chatted with Matheasy',
              subtitle: 'Asked your AI tutor for help',
              epochMillis: now.millisecondsSinceEpoch,
            )
          : null,
    );
  }

  /// Appends a pre-built activity (from the achievement engine / milestones) and
  /// marks its day as a learning day.
  void logActivity(LearningActivity activity) => _apply(
        day: _epochDay(DateTime.fromMillisecondsSinceEpoch(activity.epochMillis)),
        activity: activity,
      );

  /// Clears all analytics (tests / a future "reset progress").
  void reset() {
    state = ProgressStats.empty;
    unawaited(ref.read(progressStatsRepositoryProvider).save(ProgressStats.empty));
  }

  void _apply({
    int? scans,
    int? tutorUses,
    int? day,
    LearningActivity? activity,
  }) {
    final learningDays =
        day == null ? state.learningDays : {...state.learningDays, day};
    final recentActivity = activity == null
        ? state.recentActivity
        : [activity, ...state.recentActivity].take(ProgressStats.maxActivity).toList();

    final updated = state.copyWith(
      scans: scans,
      tutorUses: tutorUses,
      learningDays: learningDays,
      recentActivity: recentActivity,
    );
    state = updated;
    unawaited(ref.read(progressStatsRepositoryProvider).save(updated));
  }

  static int _epochDay(DateTime dt) =>
      DateTime.utc(dt.year, dt.month, dt.day).millisecondsSinceEpoch ~/
          Duration.millisecondsPerDay;
}
