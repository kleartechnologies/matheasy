import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../domain/purchase_result.dart';
import '../domain/subscription_plan.dart';
import '../domain/subscription_status.dart';
import 'subscription_service.dart';

part 'subscription_controller.g.dart';

/// The single source of truth for the user's subscription entitlement.
///
/// Subscribes to the [SubscriptionService]'s status stream (RevenueCat, or the
/// offline fallback) and projects it into a [SubscriptionStatus]. Kept alive for
/// the whole app so the entitlement survives navigation and the router can gate
/// on it. Seeds synchronously from the service's cached status so the first
/// frame already reflects the last-known plan.
@Riverpod(keepAlive: true)
class SubscriptionController extends _$SubscriptionController {
  StreamSubscription<SubscriptionStatus>? _sub;

  @override
  SubscriptionStatus build() {
    final service = ref.watch(subscriptionServiceProvider);
    _sub = service.statusChanges().listen((status) => state = status);
    ref.onDispose(() => _sub?.cancel());
    return service.currentStatus;
  }

  /// Buys [plan]. The resulting status arrives via the stream; on success we
  /// also set it directly so the UI reacts without waiting for the round-trip.
  Future<PurchaseResult> purchase(SubscriptionPlan plan) async {
    final result = await ref.read(subscriptionServiceProvider).purchase(plan);
    if (result is PurchaseSuccess) {
      state = result.status;
      unawaited(ref.read(analyticsServiceProvider).logEvent(
          AnalyticsEvent.subscriptionPurchased(plan: plan.name)));
    }
    return result;
  }

  /// Restores previously-purchased entitlements.
  Future<PurchaseResult> restore() async {
    final result = await ref.read(subscriptionServiceProvider).restore();
    if (result is PurchaseSuccess) {
      state = result.status;
      unawaited(ref
          .read(analyticsServiceProvider)
          .logEvent(AnalyticsEvent.subscriptionRestored()));
    }
    return result;
  }

  /// Forces a refresh from the source of truth.
  Future<void> refresh() =>
      ref.read(subscriptionServiceProvider).refresh();
}

/// Whether the user holds the active `pro` entitlement — the app-wide gate the
/// router and premium-only features read. Replaces the Stage 1 placeholder
/// `PremiumController`; now sourced from RevenueCat.
@Riverpod(keepAlive: true)
bool isPro(Ref ref) => ref.watch(subscriptionControllerProvider).isPro;
