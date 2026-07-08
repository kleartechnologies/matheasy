import 'subscription_plan.dart';

/// A purchasable plan paired with its live, localized store price.
///
/// Built from a RevenueCat `Package` (the SDK type never leaves the service
/// layer). The paywall renders these so prices always match what the store will
/// actually charge — currency, tax and regional pricing included.
class SubscriptionProduct {
  const SubscriptionProduct({
    required this.plan,
    required this.priceString,
    this.pricePerMonthString,
    this.rawPrice,
    this.currencyCode,
  });

  /// The plan this product represents.
  final SubscriptionPlan plan;

  /// Localized total price for the billing period (e.g. `RM149.99`).
  final String priceString;

  /// Localized per-month price for annual plans (e.g. `RM12.50`), when the store
  /// provides it — used for the "just RM x/mo" annual value line.
  final String? pricePerMonthString;

  /// Raw numeric price (store currency), for computing savings across plans.
  final double? rawPrice;

  /// ISO currency code of [rawPrice] (e.g. `MYR`).
  final String? currencyCode;

  /// A display fallback product, used when the live catalog can't be loaded, so
  /// the paywall still renders coherent pricing.
  factory SubscriptionProduct.fallback(SubscriptionPlan plan) =>
      SubscriptionProduct(plan: plan, priceString: plan.fallbackPrice);

  @override
  bool operator ==(Object other) =>
      other is SubscriptionProduct &&
      other.plan == plan &&
      other.priceString == priceString &&
      other.pricePerMonthString == pricePerMonthString &&
      other.rawPrice == rawPrice &&
      other.currencyCode == currencyCode;

  @override
  int get hashCode =>
      Object.hash(plan, priceString, pricePerMonthString, rawPrice, currencyCode);
}
