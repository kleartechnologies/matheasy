import 'usage_counts.dart';
import 'usage_quota.dart';

/// A computed, read-only view over the usage ledger — the single object the UI
/// and gating logic consult.
///
/// It folds together the applicable [UsageQuota], the current [UsageCounts] and
/// the Pro flag, so callers ask plain questions (`canScan`, `remainingScans`)
/// without re-deriving the "is this feature unlimited?" branch everywhere. Pro
/// users are unconditionally unlimited.
class UsageSnapshot {
  const UsageSnapshot({
    required this.counts,
    required this.quota,
    required this.isPro,
  });

  final UsageCounts counts;
  final UsageQuota quota;
  final bool isPro;

  int _limitFor(UsageFeature feature) => switch (feature) {
        UsageFeature.scan => quota.scans,
        UsageFeature.numiMessage => quota.numiMessages,
        UsageFeature.practiceQuestion => quota.practiceQuestions,
      };

  /// Whether [feature] is uncapped (Pro, or an explicitly unlimited quota).
  bool isUnlimited(UsageFeature feature) =>
      isPro || UsageQuota.isUnlimited(_limitFor(feature));

  /// Whether the user may perform [feature] once more right now.
  bool can(UsageFeature feature) =>
      isUnlimited(feature) || counts.usedFor(feature) < _limitFor(feature);

  /// Remaining allowance for [feature]; [UsageQuota.unlimited] when uncapped,
  /// otherwise clamped at 0 (never negative).
  int remaining(UsageFeature feature) {
    if (isUnlimited(feature)) return UsageQuota.unlimited;
    final left = _limitFor(feature) - counts.usedFor(feature);
    return left < 0 ? 0 : left;
  }

  /// The cap for [feature] ([UsageQuota.unlimited] when uncapped).
  int limit(UsageFeature feature) =>
      isUnlimited(feature) ? UsageQuota.unlimited : _limitFor(feature);

  // ---- Named conveniences for call sites ----
  bool get canScan => can(UsageFeature.scan);
  bool get canSendNumiMessage => can(UsageFeature.numiMessage);
  bool get canGeneratePractice => can(UsageFeature.practiceQuestion);

  int get remainingScans => remaining(UsageFeature.scan);
  int get remainingNumiMessages => remaining(UsageFeature.numiMessage);
  int get remainingPracticeQuestions => remaining(UsageFeature.practiceQuestion);
}
