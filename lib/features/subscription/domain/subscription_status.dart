import 'entitlement.dart';
import 'subscription_plan.dart';

/// Where an active subscription was purchased. Kept plugin-free (the RevenueCat
/// `Store` enum is mapped into this) so the domain has no SDK dependency.
enum SubscriptionStore { appStore, playStore, stripe, promotional, unknown }

/// An immutable snapshot of the user's subscription entitlement.
///
/// This is the app-facing projection of RevenueCat's `CustomerInfo` — the
/// controller and UI depend only on this, never on the SDK types. RevenueCat
/// remains the source of truth; a copy is cached locally so the app opens with
/// the last-known state before the first network refresh resolves.
class SubscriptionStatus {
  const SubscriptionStatus({
    required this.entitlement,
    this.activePlan,
    this.willRenew = false,
    this.expiresAt,
    this.store = SubscriptionStore.unknown,
    this.isSandbox = false,
    this.hasBillingIssue = false,
    this.unsubscribeDetected = false,
    this.managementUrl,
  });

  /// The free (no entitlement) baseline — the app's default before any data.
  static const SubscriptionStatus free =
      SubscriptionStatus(entitlement: Entitlement.none);

  /// The entitlement the user currently holds.
  final Entitlement entitlement;

  /// The plan backing the entitlement, if resolvable from the product id.
  final SubscriptionPlan? activePlan;

  /// Whether the store will auto-renew at [expiresAt].
  final bool willRenew;

  /// When the current period ends (null for the free tier / lifetime).
  final DateTime? expiresAt;

  /// The store the subscription was bought through.
  final SubscriptionStore store;

  /// Whether this is a sandbox/test purchase (dev + review builds).
  final bool isSandbox;

  /// Whether the store flagged a billing problem on the subscription.
  final bool hasBillingIssue;

  /// Whether the user has turned off auto-renew (cancelled but still active).
  final bool unsubscribeDetected;

  /// Deep link to the platform's subscription management page, when available.
  final String? managementUrl;

  /// Whether the user has an active paid entitlement.
  bool get isPro => entitlement.grants(Entitlement.pro);

  /// True once the user has paid but auto-renew is off — access continues until
  /// [expiresAt] and then lapses. Drives the "cancelled, active until…"
  /// messaging on the manage-subscription screen.
  bool get isCancelledButActive =>
      isPro && expiresAt != null && (!willRenew || unsubscribeDetected);

  SubscriptionStatus copyWith({
    Entitlement? entitlement,
    SubscriptionPlan? activePlan,
    bool? willRenew,
    DateTime? expiresAt,
    SubscriptionStore? store,
    bool? isSandbox,
    bool? hasBillingIssue,
    bool? unsubscribeDetected,
    String? managementUrl,
  }) {
    return SubscriptionStatus(
      entitlement: entitlement ?? this.entitlement,
      activePlan: activePlan ?? this.activePlan,
      willRenew: willRenew ?? this.willRenew,
      expiresAt: expiresAt ?? this.expiresAt,
      store: store ?? this.store,
      isSandbox: isSandbox ?? this.isSandbox,
      hasBillingIssue: hasBillingIssue ?? this.hasBillingIssue,
      unsubscribeDetected: unsubscribeDetected ?? this.unsubscribeDetected,
      managementUrl: managementUrl ?? this.managementUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SubscriptionStatus &&
      other.entitlement == entitlement &&
      other.activePlan == activePlan &&
      other.willRenew == willRenew &&
      other.expiresAt == expiresAt &&
      other.store == store &&
      other.isSandbox == isSandbox &&
      other.hasBillingIssue == hasBillingIssue &&
      other.unsubscribeDetected == unsubscribeDetected &&
      other.managementUrl == managementUrl;

  @override
  int get hashCode => Object.hash(
        entitlement,
        activePlan,
        willRenew,
        expiresAt,
        store,
        isSandbox,
        hasBillingIssue,
        unsubscribeDetected,
        managementUrl,
      );
}
