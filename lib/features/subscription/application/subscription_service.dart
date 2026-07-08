import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/purchase_result.dart';
import '../domain/subscription_plan.dart';
import '../domain/subscription_product.dart';
import '../domain/subscription_status.dart';
import 'local_subscription_service.dart';
import 'revenuecat_subscription_service.dart';
import 'subscription_cache.dart';

/// The subscription/billing provider — the one seam RevenueCat plugs into.
///
/// Mirrors [AuthService]: the controllers and UI depend only on this interface
/// and the domain models, so the backing implementation
/// ([RevenueCatSubscriptionService], or the offline [LocalSubscriptionService]
/// fallback) can be swapped by overriding [subscriptionServiceProvider] with
/// zero UI churn. The `purchases_flutter` SDK is quarantined behind the
/// RevenueCat implementation and never imported elsewhere.
abstract interface class SubscriptionService {
  /// Emits the current [SubscriptionStatus] immediately and on every change
  /// (RevenueCat customer-info updates, or local grants).
  Stream<SubscriptionStatus> statusChanges();

  /// The last-known status (synchronous) — seeded from the local cache so the
  /// app opens with a sensible entitlement before the first refresh.
  SubscriptionStatus get currentStatus;

  /// Loads the purchasable plans with live, localized store prices. Falls back
  /// to display prices if the catalog can't be fetched, so the paywall always
  /// renders.
  Future<List<SubscriptionProduct>> loadProducts();

  /// Buys [plan]. Returns a typed [PurchaseResult]; never throws for a user
  /// cancellation (that returns [PurchaseCancelled]).
  Future<PurchaseResult> purchase(SubscriptionPlan plan);

  /// Restores previously-purchased entitlements for this store account.
  Future<PurchaseResult> restore();

  /// Forces a status refresh from the source of truth.
  Future<void> refresh();

  /// Releases listeners / stream controllers.
  void dispose();
}

/// Whether real RevenueCat initialized this launch. Overridden in `bootstrap`
/// with the real result; defaults to `false` so tests and a not-yet-provisioned
/// checkout resolve to the offline [LocalSubscriptionService].
final Provider<bool> revenueCatReadyProvider = Provider<bool>((ref) => false);

/// Provides the active [SubscriptionService]. When RevenueCat is ready this is
/// the real [RevenueCatSubscriptionService]; otherwise the [LocalSubscriptionService]
/// keeps the app fully usable (fallback prices, local grant for demos/dev).
final Provider<SubscriptionService> subscriptionServiceProvider =
    Provider<SubscriptionService>((ref) {
  final cache = SubscriptionCache(ref.watch(preferencesStoreProvider));
  final service = ref.watch(revenueCatReadyProvider)
      ? RevenueCatSubscriptionService(cache)
      : LocalSubscriptionService(cache);
  ref.onDispose(service.dispose);
  return service;
});
