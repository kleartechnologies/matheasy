import 'entitlement.dart';

/// The subscription plans Matheasy sells (plus the implicit [free] tier).
///
/// Each paid plan maps to a RevenueCat product identifier and the [Entitlement]
/// it grants. Live, localized prices come from the store at runtime
/// (`SubscriptionProduct`); the constants here are display fallbacks used when
/// the store catalog is unavailable (offline, or the unconfigured fallback).
enum SubscriptionPlan {
  free(
    productId: null,
    entitlement: Entitlement.none,
    fallbackPrice: 'RM0',
    period: 'forever',
  ),
  proMonthly(
    productId: 'matheasy_pro_monthly',
    entitlement: Entitlement.pro,
    fallbackPrice: 'RM19.99',
    period: 'month',
  ),
  proAnnual(
    productId: 'matheasy_pro_annual',
    entitlement: Entitlement.pro,
    fallbackPrice: 'RM149.99',
    period: 'year',
  );

  const SubscriptionPlan({
    required this.productId,
    required this.entitlement,
    required this.fallbackPrice,
    required this.period,
  });

  /// The RevenueCat / store product identifier, or `null` for [free].
  final String? productId;

  /// The entitlement this plan unlocks.
  final Entitlement entitlement;

  /// Display price used only when the live store price is unavailable.
  final String fallbackPrice;

  /// The billing period noun (`month`, `year`, `forever`).
  final String period;

  bool get isPaid => entitlement.isPaid;
  bool get isAnnual => this == SubscriptionPlan.proAnnual;

  /// Resolves a plan from a store product identifier, or `null` if unknown.
  static SubscriptionPlan? fromProductId(String? id) {
    if (id == null) return null;
    for (final plan in SubscriptionPlan.values) {
      if (plan.productId == id) return plan;
    }
    return null;
  }

  /// The paid plans shown on the paywall, annual first (the recommended pick).
  static const List<SubscriptionPlan> paidPlans = [proAnnual, proMonthly];
}
