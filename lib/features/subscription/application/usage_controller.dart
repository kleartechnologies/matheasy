import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/usage_counts.dart';
import '../domain/usage_quota.dart';
import '../domain/usage_snapshot.dart';
import 'subscription_controller.dart';
import 'usage_tracker.dart';

part 'usage_controller.g.dart';

/// The local usage ledger — records free-tier consumption of scans, AI tutor
/// messages and generated practice questions. Kept alive; hydrates on build and
/// persists every change fire-and-forget (mirrors `StatsController`).
///
/// This is the single mutator of [UsageCounts]; gating reads the derived
/// [usageSnapshotProvider], which folds these counts against the tier quota.
/// Counts still increment for Pro users (harmless — the snapshot reports
/// unlimited regardless), so a lapse back to free reflects real usage.
@Riverpod(keepAlive: true)
class UsageController extends _$UsageController {
  @override
  UsageCounts build() => ref.read(usageTrackerProvider).load();

  /// Records a consumed scan.
  void recordScan() =>
      _update(state.copyWith(scansUsed: state.scansUsed + 1));

  /// Records an AI tutor message sent by the user.
  void recordTutorMessage() =>
      _update(state.copyWith(tutorMessagesUsed: state.tutorMessagesUsed + 1));

  /// Records [count] freshly-generated practice questions (a session's worth).
  void recordPracticeGenerated(int count) {
    if (count <= 0) return;
    _update(
      state.copyWith(
        practiceQuestionsGenerated: state.practiceQuestionsGenerated + count,
      ),
    );
  }

  /// Resets the ledger (used by "Delete Account" / reset progress).
  void reset() => _update(UsageCounts.empty);

  void _update(UsageCounts next) {
    state = next;
    unawaited(ref.read(usageTrackerProvider).save(next));
  }
}

/// The computed usage view the UI and gating consult. Reacts to both the counts
/// and the Pro entitlement, so the moment a purchase lands every gate reopens.
@riverpod
UsageSnapshot usageSnapshot(Ref ref) {
  return UsageSnapshot(
    counts: ref.watch(usageControllerProvider),
    quota: UsageQuota.free,
    isPro: ref.watch(isProProvider),
  );
}
