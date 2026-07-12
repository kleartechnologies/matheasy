import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/app_user.dart';
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

  /// Associates the billing identity with [appUserId] (the Firebase uid), so a
  /// purchase is attributed to this account and the RevenueCat webhook can map
  /// `app_user_id` → the user's Firestore doc. Call after a real sign-in.
  Future<void> logIn(String appUserId);

  /// Clears the billing identity (returns to an anonymous id) on sign-out or a
  /// guest session, so the next user's purchases aren't attributed here.
  Future<void> logOut();

  /// Feeds ad-network matching identifiers to the billing backend so server-side
  /// purchase events (RevenueCat → Meta Conversions API) attribute to the ad
  /// click: the Facebook anonymous id ([fbAnonymousId]) plus the device
  /// identifiers (`$idfa`/`$idfv`/`$gpsAdId`). Called after the ATT decision so a
  /// real (non-zeroed) IDFA is captured when authorized. No-op on the offline
  /// fallback (there is no backend to attribute a purchase to).
  Future<void> attachAdAttribution({String? fbAnonymousId});

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

/// Keeps the billing identity in step with the signed-in user: on a real
/// sign-in it calls `logIn(uid)` so purchases attribute to the Firebase uid (and
/// the RevenueCat webhook can map `app_user_id` → their Firestore doc); guests /
/// sign-out fall back to an anonymous id via `logOut`.
///
/// Deliberately its own provider (kept alive by [AppShell]) rather than folded
/// into [subscriptionControllerProvider], so it runs only during real app use —
/// not on every `isPro` entitlement check.
final Provider<void> revenueCatIdentitySyncProvider = Provider<void>((ref) {
  void sync(AppUser? user) {
    final service = ref.read(subscriptionServiceProvider);
    if (user != null && !user.isGuest) {
      unawaited(service.logIn(user.id));
    } else {
      unawaited(service.logOut());
    }
  }

  // fireImmediately covers the already-signed-in-at-launch case.
  ref.listen<AppUser?>(
    currentUserProvider,
    (_, next) => sync(next),
    fireImmediately: true,
  );
});
