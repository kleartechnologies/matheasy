import 'usage_counts.dart';
import 'usage_quota.dart';

/// The server's authoritative view of this user's free-tier usage — the parsed
/// `usageStatus` callable response.
///
/// **This is not the gate.** The gate is `usage/guard.ts`, re-run from the
/// database on every metered request. This object exists so the UI draws a meter
/// that AGREES with that gate instead of guessing from a local counter: after a
/// reinstall, an account switch, or a cleared preferences file, the local tally
/// reads zero while the server still remembers. Folding this in is what stops
/// the app from cheerfully offering five scans it will then be refused.
///
/// Everything here is display truth. A user who edits it gets a different meter
/// and exactly the same number of scans.
class ServerUsage {
  const ServerUsage({
    required this.isPro,
    required this.entitlement,
    required this.counts,
    required this.quota,
    this.expiresAtMs,
    this.serverNowMs,
  });

  /// Whether the SERVER resolved this account to an active Pro entitlement
  /// (including cancelled-but-still-paid and billing-retry grace).
  final bool isPro;

  /// The resolved entitlement state: `active`, `grace`, `cancelled`, `expired`
  /// or `none`. Carried for diagnostics and future billing-issue messaging.
  final String entitlement;

  /// When the current period ends, if known.
  final int? expiresAtMs;

  /// The server's wall-clock time when this response was built (epoch ms), if
  /// the backend sent one. Used to persist a device-clock offset for the
  /// trusted clock — never displayed.
  final int? serverNowMs;

  /// Effective lifetime usage — the maximum across this account and this
  /// installation, which is why signing into a fresh account does not reset it.
  final UsageCounts counts;

  /// The live free-tier ceilings, straight from Remote Config. The client no
  /// longer has the last word on what "5 scans" means.
  final UsageQuota quota;

  /// Parses the `usageStatus` response, degrading every malformed field to a
  /// safe default rather than throwing — a bad payload must never lock a
  /// student out of an allowance they still have.
  factory ServerUsage.fromJson(Map<String, dynamic> json) {
    final used = _map(json['used']);
    final limits = _map(json['limits']);
    return ServerUsage(
      isPro: json['isPro'] == true,
      entitlement: json['entitlement'] is String
          ? json['entitlement'] as String
          : 'none',
      expiresAtMs: json['expiresAtMs'] is num
          ? (json['expiresAtMs'] as num).toInt()
          : null,
      serverNowMs: json['serverNowMs'] is num
          ? (json['serverNowMs'] as num).toInt()
          : null,
      counts: UsageCounts(
        scansUsed: _count(used['scans']),
        tutorMessagesUsed: _count(used['tutorMessages']),
        practiceQuestionsGenerated: _count(used['practiceQuestions']),
      ),
      quota: UsageQuota(
        scans: _limit(limits['scans'], UsageQuota.free.scans),
        tutorMessages:
            _limit(limits['tutorMessages'], UsageQuota.free.tutorMessages),
        practiceQuestions: _limit(
          limits['practiceQuestions'],
          UsageQuota.free.practiceQuestions,
        ),
      ),
    );
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  /// A used-count is never negative — a negative one would read as extra
  /// allowance.
  static int _count(Object? value) {
    if (value is! num) return 0;
    final n = value.toInt();
    return n < 0 ? 0 : n;
  }

  /// A limit may legitimately be [UsageQuota.unlimited] (`-1`); anything else
  /// negative, or missing, falls back to the compiled free-tier number.
  static int _limit(Object? value, int fallback) {
    if (value is! num) return fallback;
    final n = value.toInt();
    if (n == UsageQuota.unlimited) return UsageQuota.unlimited;
    return n < 0 ? fallback : n;
  }

  @override
  bool operator ==(Object other) =>
      other is ServerUsage &&
      other.isPro == isPro &&
      other.entitlement == entitlement &&
      other.expiresAtMs == expiresAtMs &&
      other.serverNowMs == serverNowMs &&
      other.counts == counts &&
      other.quota == quota;

  @override
  int get hashCode =>
      Object.hash(isPro, entitlement, expiresAtMs, serverNowMs, counts, quota);
}
