import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;

import '../domain/entitlement.dart';
import '../domain/purchase_result.dart';
import '../domain/subscription_plan.dart';
import '../domain/subscription_product.dart';
import '../domain/subscription_status.dart';
import 'subscription_cache.dart';
import 'subscription_service.dart';

/// Offline [SubscriptionService] used when RevenueCat isn't configured (a fresh
/// checkout with placeholder keys, an unsupported platform, or tests).
///
/// It keeps the app fully usable: fallback prices power the paywall, and a
/// "purchase" grants the `pro` entitlement locally and persists it via
/// [SubscriptionCache] so it survives relaunches — enough for a demo/dev flow
/// and deterministic tests. No network, no SDK. Restore returns whatever was
/// locally granted.
class LocalSubscriptionService implements SubscriptionService {
  LocalSubscriptionService(this._cache)
    : _current = _cache.read() ?? SubscriptionStatus.free {
    // Prime late subscribers with the current value.
    _controller.onListen = () => _controller.add(_current);
  }

  final SubscriptionCache _cache;
  final StreamController<SubscriptionStatus> _controller =
      StreamController<SubscriptionStatus>.broadcast();

  SubscriptionStatus _current;

  @override
  SubscriptionStatus get currentStatus => _current;

  @override
  Stream<SubscriptionStatus> statusChanges() => _controller.stream;

  @override
  Future<List<SubscriptionProduct>> loadProducts() async => [
    for (final plan in SubscriptionPlan.paidPlans)
      SubscriptionProduct.fallback(plan),
  ];

  @override
  Future<PurchaseResult> purchase(SubscriptionPlan plan) async {
    if (!plan.isPaid) {
      return const PurchaseFailure(
        'That plan cannot be purchased.',
        isRecoverable: false,
      );
    }
    // The local grant is a dev/demo convenience only. In a release build this
    // fallback means RevenueCat isn't configured, so never hand out Pro for
    // free — surface an unavailable error instead.
    if (kReleaseMode) {
      return const PurchaseFailure(
        'Subscriptions are temporarily unavailable. Please try again later.',
      );
    }
    final status = SubscriptionStatus(
      entitlement: plan.entitlement,
      activePlan: plan,
      willRenew: true,
      isSandbox: true,
    );
    await _emit(status);
    return PurchaseSuccess(status);
  }

  @override
  Future<PurchaseResult> restore() async {
    if (_current.isPro) return PurchaseSuccess(_current);
    return const PurchaseNothingToRestore();
  }

  @override
  Future<void> refresh() async {
    // Nothing to sync offline; re-emit so listeners re-settle if needed.
    _controller.add(_current);
  }

  // No billing backend offline, so identity is a no-op (there's nothing to
  // attribute a purchase to). Kept to satisfy the interface.
  @override
  Future<void> logIn(String appUserId) async {}

  @override
  Future<void> logOut() async {}

  @override
  Future<void> attachAdAttribution({String? fbAnonymousId}) async {}

  Future<void> _emit(SubscriptionStatus status) async {
    _current = status;
    await _cache.write(status);
    if (!_controller.isClosed) _controller.add(status);
  }

  @override
  void dispose() {
    unawaited(_controller.close());
  }

  /// Test/dev hook: whether this fallback currently holds a granted entitlement.
  bool get hasLocalEntitlement => _current.entitlement != Entitlement.none;
}
