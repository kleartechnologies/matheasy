import 'subscription_status.dart';

/// The outcome of a purchase or restore attempt.
///
/// A sealed hierarchy so callers must handle every case (mirrors the app's
/// other state unions like `ScanState`). The UI switches on the concrete type
/// to decide between a celebration, a quiet dismissal (user cancelled) or an
/// error message.
sealed class PurchaseResult {
  const PurchaseResult();
}

/// The purchase (or restore) completed and the entitlement is now active.
class PurchaseSuccess extends PurchaseResult {
  const PurchaseSuccess(this.status);

  final SubscriptionStatus status;
}

/// The user dismissed the native purchase sheet — not an error, show nothing.
class PurchaseCancelled extends PurchaseResult {
  const PurchaseCancelled();
}

/// The payment is deferred/pending store approval (e.g. Ask to Buy). The
/// entitlement will arrive later via the status stream.
class PurchasePending extends PurchaseResult {
  const PurchasePending();
}

/// A restore found no active entitlements to recover.
class PurchaseNothingToRestore extends PurchaseResult {
  const PurchaseNothingToRestore();
}

/// The purchase failed for a store/network/config reason. [message] is a
/// user-safe, already-humanized string.
class PurchaseFailure extends PurchaseResult {
  const PurchaseFailure(this.message, {this.isRecoverable = true});

  final String message;

  /// Whether retrying could plausibly succeed (network) vs. a hard stop
  /// (not-allowed, config error).
  final bool isRecoverable;
}
