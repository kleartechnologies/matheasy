import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
// The SDK also exports a `PurchaseResult`; hide it so the app's domain
// `PurchaseResult` is the only one in scope (we read the SDK result via type
// inference only).
import 'package:purchases_flutter/purchases_flutter.dart' hide PurchaseResult;

import '../../../core/config/revenuecat_config.dart';
import '../../../core/utils/app_logger.dart';
import '../domain/entitlement.dart';
import '../domain/purchase_result.dart';
import '../domain/subscription_plan.dart';
import '../domain/subscription_product.dart';
import '../domain/subscription_status.dart';
import 'subscription_cache.dart';
import 'subscription_service.dart';

/// The real, RevenueCat-backed [SubscriptionService].
///
/// This is the ONLY file that imports `purchases_flutter` — the SDK stays
/// quarantined here, exactly like Firebase lives only behind
/// `FirebaseAuthService`. It maps RevenueCat's `CustomerInfo`/`Package` types
/// onto the app's plugin-free domain models and translates store errors into
/// typed [PurchaseResult]s.
///
/// `Purchases.configure(...)` is performed once in `bootstrap` before this is
/// constructed; here we attach the update listener, hydrate the current status
/// and expose purchase/restore.
class RevenueCatSubscriptionService implements SubscriptionService {
  RevenueCatSubscriptionService(this._cache)
    : _current = _cache.read() ?? SubscriptionStatus.free {
    _controller.onListen = () => _controller.add(_current);
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
    unawaited(refresh());
  }

  final SubscriptionCache _cache;
  final StreamController<SubscriptionStatus> _controller =
      StreamController<SubscriptionStatus>.broadcast();

  SubscriptionStatus _current;

  @override
  SubscriptionStatus get currentStatus => _current;

  @override
  Stream<SubscriptionStatus> statusChanges() => _controller.stream;

  void _onCustomerInfo(CustomerInfo info) => _apply(_mapCustomerInfo(info));

  @override
  Future<void> refresh() async {
    try {
      final info = await Purchases.getCustomerInfo();
      _apply(_mapCustomerInfo(info));
    } on PlatformException catch (error) {
      AppLogger.error('RevenueCat getCustomerInfo failed', error: error);
    }
  }

  @override
  Future<List<SubscriptionProduct>> loadProducts() async {
    try {
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;
      if (offering == null) return _fallbackProducts();

      final products = <SubscriptionProduct>[];
      for (final plan in SubscriptionPlan.paidPlans) {
        final package = _packageFor(offering, plan);
        products.add(
          package == null
              ? SubscriptionProduct.fallback(plan)
              : _mapPackage(plan, package),
        );
      }
      return products;
    } on PlatformException catch (error) {
      AppLogger.error('RevenueCat getOfferings failed', error: error);
      return _fallbackProducts();
    }
  }

  @override
  Future<PurchaseResult> purchase(SubscriptionPlan plan) async {
    if (!plan.isPaid) {
      return const PurchaseFailure(
        'That plan cannot be purchased.',
        isRecoverable: false,
      );
    }
    try {
      final offerings = await Purchases.getOfferings();
      final offering = offerings.current;
      final package = offering == null ? null : _packageFor(offering, plan);
      if (package == null) {
        return const PurchaseFailure(
          "That plan isn't available right now. Please try again later.",
        );
      }
      final result = await Purchases.purchase(PurchaseParams.package(package));
      final status = _mapCustomerInfo(result.customerInfo);
      _apply(status);
      return status.isPro ? PurchaseSuccess(status) : const PurchasePending();
    } on PlatformException catch (error) {
      return await _mapPurchaseError(error);
    }
  }

  @override
  Future<PurchaseResult> restore() async {
    try {
      final info = await Purchases.restorePurchases();
      final status = _mapCustomerInfo(info);
      _apply(status);
      return status.isPro
          ? PurchaseSuccess(status)
          : const PurchaseNothingToRestore();
    } on PlatformException catch (error) {
      return await _mapPurchaseError(error);
    }
  }

  // ---- Mapping: SDK types → domain ----

  SubscriptionStatus _mapCustomerInfo(CustomerInfo info) {
    final entitlement =
        info.entitlements.active[RevenueCatConfig.entitlementId];
    if (entitlement == null || !entitlement.isActive) {
      return SubscriptionStatus(
        entitlement: Entitlement.none,
        managementUrl: info.managementURL,
      );
    }
    return SubscriptionStatus(
      entitlement: Entitlement.pro,
      activePlan: SubscriptionPlan.fromProductId(entitlement.productIdentifier),
      willRenew: entitlement.willRenew,
      expiresAt: DateTime.tryParse(entitlement.expirationDate ?? ''),
      store: _mapStore(entitlement.store),
      isSandbox: entitlement.isSandbox,
      hasBillingIssue: entitlement.billingIssueDetectedAt != null,
      unsubscribeDetected: entitlement.unsubscribeDetectedAt != null,
      managementUrl: info.managementURL,
    );
  }

  SubscriptionProduct _mapPackage(SubscriptionPlan plan, Package package) {
    final product = package.storeProduct;
    return SubscriptionProduct(
      plan: plan,
      priceString: product.priceString,
      pricePerMonthString: product.pricePerMonthString,
      rawPrice: product.price,
      currencyCode: product.currencyCode,
    );
  }

  Package? _packageFor(Offering offering, SubscriptionPlan plan) {
    // Prefer the semantic slot, then fall back to matching the product id, so
    // the wiring survives non-standard offering setups.
    final semantic = plan.isAnnual ? offering.annual : offering.monthly;
    if (semantic != null) return semantic;
    for (final package in offering.availablePackages) {
      if (package.storeProduct.identifier == plan.productId) return package;
    }
    return null;
  }

  SubscriptionStore _mapStore(Store store) => switch (store) {
    Store.appStore || Store.macAppStore => SubscriptionStore.appStore,
    Store.playStore || Store.amazon => SubscriptionStore.playStore,
    Store.stripe ||
    Store.rcBilling ||
    Store.paddle ||
    Store.externalStore => SubscriptionStore.stripe,
    Store.promotional => SubscriptionStore.promotional,
    _ => SubscriptionStore.unknown,
  };

  Future<PurchaseResult> _mapPurchaseError(PlatformException error) async {
    final code = PurchasesErrorHelper.getErrorCode(error);
    switch (code) {
      case PurchasesErrorCode.purchaseCancelledError:
        return const PurchaseCancelled();
      case PurchasesErrorCode.paymentPendingError:
        return const PurchasePending();
      case PurchasesErrorCode.productAlreadyPurchasedError:
        // The store owns the product but our entitlement may be stale (reinstall
        // / sync race). Re-sync before claiming success, so we never celebrate a
        // purchase the user isn't actually entitled to.
        await refresh();
        return _current.isPro
            ? PurchaseSuccess(_current)
            : const PurchasePending();
      case PurchasesErrorCode.networkError:
        return const PurchaseFailure(
          'Network problem — check your connection and try again.',
        );
      case PurchasesErrorCode.purchaseNotAllowedError:
      case PurchasesErrorCode.purchaseInvalidError:
        return const PurchaseFailure(
          "This device can't complete the purchase.",
          isRecoverable: false,
        );
      case PurchasesErrorCode.storeProblemError:
        return const PurchaseFailure(
          'The store had a problem. Please try again in a moment.',
        );
      default:
        AppLogger.error('RevenueCat purchase failed', error: error);
        return const PurchaseFailure(
          'Something went wrong with the purchase. Please try again.',
        );
    }
  }

  List<SubscriptionProduct> _fallbackProducts() => [
    for (final plan in SubscriptionPlan.paidPlans)
      SubscriptionProduct.fallback(plan),
  ];

  void _apply(SubscriptionStatus status) {
    if (status == _current) return;
    _current = status;
    unawaited(_cache.write(status));
    if (!_controller.isClosed) _controller.add(status);
  }

  @override
  void dispose() {
    Purchases.removeCustomerInfoUpdateListener(_onCustomerInfo);
    unawaited(_controller.close());
  }
}
