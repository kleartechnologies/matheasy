import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/usage_counts.dart';
import '../domain/usage_quota.dart';
import '../domain/usage_snapshot.dart';
import 'server_usage_controller.dart';
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

/// The computed usage view the UI and gating consult. Reacts to the counts, the
/// Pro entitlement and the server's meter, so the moment a purchase lands every
/// gate reopens — and the moment the server's number arrives, the meter tells
/// the truth.
///
/// The server's view wins where the two disagree, in the only direction that is
/// safe to be wrong in:
///
///  * **counts** — the LARGER of local and server. The server's figure is the
///    effective one (max across this account and this installation), so a fresh
///    account on a spent device, a reinstall or a cleared preferences file shows
///    the usage that will actually be enforced rather than a hopeful zero. Local
///    can still be ahead of it between a scan and the next refresh, and that is
///    why it is a max and not an adoption.
///  * **quota** — the server's live Remote Config limits when known, so the
///    ceiling can be tuned without shipping a build. `UsageQuota.free` is the
///    compiled fallback.
///  * **isPro** — either source saying yes is yes. RevenueCat's local cache is
///    fresher right after a purchase; the server's is fresher after a renewal or
///    a grace period. Being generous here is a UX call only — the server still
///    refuses anything the entitlement doesn't cover.
///
/// This remains PRESENTATION. Every real decision is re-made in
/// `functions/src/usage/guard.ts`, from the database, on the next request.
@riverpod
UsageSnapshot usageSnapshot(Ref ref) {
  final local = ref.watch(usageControllerProvider);
  final server = ref.watch(serverUsageControllerProvider);
  return UsageSnapshot(
    counts: server == null ? local : local.mergedWith(server.counts),
    quota: server?.quota ?? UsageQuota.free,
    isPro: ref.watch(isProProvider) || (server?.isPro ?? false),
  );
}
