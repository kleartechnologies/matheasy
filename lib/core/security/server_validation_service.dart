import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The result of a (would-be) server-side validation.
///
/// [serverVerified] tells the caller whether an authoritative server actually
/// checked the claim, versus falling back to client trust. This lets the UI
/// proceed today (client limits apply) while making it explicit where real
/// enforcement must plug in.
class ServerValidationResult {
  const ServerValidationResult({
    required this.allowed,
    required this.serverVerified,
    this.reason,
  });

  /// The action may proceed but the server did NOT verify it — client-side
  /// limits are the only guard (the current, pre-Cloud-Function state).
  const ServerValidationResult.allowedUnverified()
      : allowed = true,
        serverVerified = false,
        reason = null;

  /// The server verified and allowed the action.
  const ServerValidationResult.allowed()
      : allowed = true,
        serverVerified = true,
        reason = null;

  /// The server verified and denied the action (quota exhausted / no
  /// entitlement / abuse).
  const ServerValidationResult.denied(this.reason)
      : allowed = false,
        serverVerified = true;

  final bool allowed;
  final bool serverVerified;
  final String? reason;
}

/// The seam for server-authoritative validation of entitlement + metered usage.
///
/// **Why this exists (never trust the client):** scan / Numi / practice quotas
/// and the Pro entitlement are enforced client-side today (fast, offline-first),
/// but a determined user can tamper with local counters. The production control
/// is a Firebase **callable function** that re-checks against the server's copy
/// of the entitlement + usage before granting a metered action.
///
/// ### Callable contract to implement (production)
/// A `CallableServerValidationService` (adding `cloud_functions`) calls:
/// * `validateEntitlement()` → `{ active: bool, tier: string }`
/// * `validateUsage({ feature: 'scan'|'numi'|'practice' })`
///   → `{ allowed: bool, remaining: int, reason?: string }`
/// The function reads the RevenueCat entitlement (via the REST API / webhook
/// mirror) and the server-side usage ledger, so client tampering is irrelevant.
///
/// Until that function is deployed, [LocalTrustServerValidationService] returns
/// `allowedUnverified` — the app runs on client-side limits, and every call site
/// is already wired to consult this seam.
abstract interface class ServerValidationService {
  Future<ServerValidationResult> validateEntitlement();

  Future<ServerValidationResult> validateUsage(String feature);
}

/// Current implementation: no server round-trip. Everything is allowed but flagged
/// `serverVerified: false`, so client-side limits remain the guard and the
/// call sites are ready for the real callable to drop in.
class LocalTrustServerValidationService implements ServerValidationService {
  const LocalTrustServerValidationService();

  @override
  Future<ServerValidationResult> validateEntitlement() async =>
      const ServerValidationResult.allowedUnverified();

  @override
  Future<ServerValidationResult> validateUsage(String feature) async =>
      const ServerValidationResult.allowedUnverified();
}

/// Provides the active [ServerValidationService]. Swap for the callable-backed
/// implementation once the Cloud Function is deployed.
final Provider<ServerValidationService> serverValidationServiceProvider =
    Provider<ServerValidationService>(
  (ref) => const LocalTrustServerValidationService(),
);
