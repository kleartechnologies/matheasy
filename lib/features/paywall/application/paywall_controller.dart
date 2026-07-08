import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../subscription/application/subscription_controller.dart';
import '../../subscription/application/subscription_service.dart';
import '../../subscription/domain/purchase_result.dart';
import '../../subscription/domain/subscription_plan.dart';
import '../../subscription/domain/subscription_product.dart';

part 'paywall_controller.g.dart';

/// Immutable state driving the paywall screen: the purchasable products (with
/// live prices), the selected plan, and transient purchase/restore progress.
@immutable
class PaywallState {
  const PaywallState({
    required this.products,
    required this.selectedPlan,
    this.loadingProducts = true,
    this.purchasing = false,
    this.restoring = false,
    this.result,
  });

  /// The catalog, seeded with display fallbacks so prices render immediately,
  /// then replaced with live store prices once [PaywallController] loads them.
  final List<SubscriptionProduct> products;

  /// The plan the pricing cards currently highlight (defaults to annual).
  final SubscriptionPlan selectedPlan;

  final bool loadingProducts;
  final bool purchasing;
  final bool restoring;

  /// The most recent purchase/restore outcome, or `null` once consumed by the
  /// screen (celebration shown / error surfaced).
  final PurchaseResult? result;

  /// Whether any purchase or restore call is in flight.
  bool get busy => purchasing || restoring;

  /// The product for [selectedPlan], if present in the catalog.
  SubscriptionProduct? get selectedProduct => productFor(selectedPlan);

  SubscriptionProduct? productFor(SubscriptionPlan plan) {
    for (final product in products) {
      if (product.plan == plan) return product;
    }
    return null;
  }

  PaywallState copyWith({
    List<SubscriptionProduct>? products,
    SubscriptionPlan? selectedPlan,
    bool? loadingProducts,
    bool? purchasing,
    bool? restoring,
    PurchaseResult? result,
    bool clearResult = false,
  }) {
    return PaywallState(
      products: products ?? this.products,
      selectedPlan: selectedPlan ?? this.selectedPlan,
      loadingProducts: loadingProducts ?? this.loadingProducts,
      purchasing: purchasing ?? this.purchasing,
      restoring: restoring ?? this.restoring,
      result: clearResult ? null : (result ?? this.result),
    );
  }

  factory PaywallState.initial() => PaywallState(
    products: [
      for (final plan in SubscriptionPlan.paidPlans)
        SubscriptionProduct.fallback(plan),
    ],
    selectedPlan: SubscriptionPlan.proAnnual,
  );
}

/// Drives the paywall: loads live products, tracks the selected plan and runs
/// the purchase/restore flow through [SubscriptionController].
///
/// Auto-disposes with the paywall route, so every open starts fresh with the
/// annual plan preselected and re-fetches the latest prices.
@riverpod
class PaywallController extends _$PaywallController {
  // The paywall auto-disposes when dismissed; the Close button stays enabled
  // during a purchase/restore, so a mid-flight dismissal can land after an
  // await. This flag guards every post-await state write (writing to a disposed
  // notifier throws), mirroring the app's other async controllers.
  bool _disposed = false;

  @override
  PaywallState build() {
    ref.onDispose(() => _disposed = true);
    unawaited(_loadProducts());
    return PaywallState.initial();
  }

  Future<void> _loadProducts() async {
    final products = await ref.read(subscriptionServiceProvider).loadProducts();
    if (_disposed) return;
    if (products.isEmpty) {
      state = state.copyWith(loadingProducts: false);
      return;
    }
    state = state.copyWith(products: products, loadingProducts: false);
  }

  /// Highlights [plan] (the tapped pricing card).
  void select(SubscriptionPlan plan) {
    if (plan == state.selectedPlan) return;
    state = state.copyWith(selectedPlan: plan);
  }

  /// Purchases the currently selected plan.
  Future<PurchaseResult> purchaseSelected() async {
    if (state.busy) return const PurchasePending();
    state = state.copyWith(purchasing: true, clearResult: true);
    final result = await ref
        .read(subscriptionControllerProvider.notifier)
        .purchase(state.selectedPlan);
    if (_disposed) return result;
    state = state.copyWith(purchasing: false, result: result);
    return result;
  }

  /// Restores previously-purchased entitlements.
  Future<PurchaseResult> restore() async {
    if (state.busy) return const PurchasePending();
    state = state.copyWith(restoring: true, clearResult: true);
    final result = await ref
        .read(subscriptionControllerProvider.notifier)
        .restore();
    if (_disposed) return result;
    state = state.copyWith(restoring: false, result: result);
    return result;
  }

  /// Clears the last result after the screen has reacted to it.
  void clearResult() => state = state.copyWith(clearResult: true);
}
