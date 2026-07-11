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

  /// The currency symbol/prefix the store returned (e.g. `RM`, `$`, `€`),
  /// derived from the localized [priceString] by stripping Unicode digits
  /// (`\p{Nd}` covers Arabic-Indic, Devanagari, etc.), whitespace and the
  /// decimal/grouping marks — so non-Latin numeral systems don't leak into the
  /// symbol. Storefront-agnostic and never hardcoded; `null` if the price string
  /// carried no symbol.
  String? get currencySymbol {
    final symbol = priceString
        .replaceAll(RegExp(r'[\p{Nd}\p{Zs}\s.,]', unicode: true), '')
        .trim();
    return symbol.isEmpty ? null : symbol;
  }

  /// The per-month price for an annual plan (e.g. `RM12.50`).
  ///
  /// Prefers the store's OWN localized [pricePerMonthString] — it already
  /// carries the correct numerals, decimal separator and symbol placement for
  /// the storefront, which a hand-built string cannot reproduce. Only when the
  /// store does not provide one do we compute the annual [rawPrice] ÷ 12
  /// (2 decimals, [currencySymbol] prepended). `null` when no price is known.
  ///
  /// This per-month figure is the paywall's only computed price; every other
  /// figure is the store's own localized string.
  String? get pricePerMonthComputed {
    final storePerMonth = pricePerMonthString;
    if (storePerMonth != null && storePerMonth.isNotEmpty) return storePerMonth;

    final price = rawPrice;
    final symbol = currencySymbol;
    if (price != null && price > 0 && symbol != null) {
      return '$symbol${(price / 12).toStringAsFixed(2)}';
    }
    return null;
  }

  /// A display fallback product, used when the live catalog can't be loaded, so
  /// the paywall still renders coherent pricing. Parses a numeric [rawPrice] out
  /// of the plan's (ASCII) fallback price so the per-month framing and the
  /// savings line stay self-consistent even offline / with a partial catalog.
  factory SubscriptionProduct.fallback(SubscriptionPlan plan) =>
      SubscriptionProduct(
        plan: plan,
        priceString: plan.fallbackPrice,
        rawPrice: double.tryParse(
          plan.fallbackPrice.replaceAll(RegExp(r'[^0-9.]'), ''),
        ),
      );

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
