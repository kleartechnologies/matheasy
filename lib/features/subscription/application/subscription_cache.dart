import 'dart:convert';

import '../../../core/persistence/preferences_store.dart';
import '../domain/entitlement.dart';
import '../domain/subscription_plan.dart';
import '../domain/subscription_status.dart';

/// Reads/writes the locally cached [SubscriptionStatus].
///
/// RevenueCat is the source of truth; this snapshot only lets the app open with
/// the last-known entitlement before the first refresh resolves (and backs the
/// offline `LocalSubscriptionService`). A corrupt payload degrades to `null`
/// (treated as free) rather than throwing.
class SubscriptionCache {
  const SubscriptionCache(this._store);

  final PreferencesStore _store;

  SubscriptionStatus? read() {
    final raw = _store.subscriptionCacheJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SubscriptionStatus(
        entitlement:
            _enumByName(Entitlement.values, map['entitlement']) ??
                Entitlement.none,
        activePlan: _enumByName(SubscriptionPlan.values, map['activePlan']),
        willRenew: map['willRenew'] == true,
        expiresAt: _dateFromMillis(map['expiresAt']),
        store: _enumByName(SubscriptionStore.values, map['store']) ??
            SubscriptionStore.unknown,
        isSandbox: map['isSandbox'] == true,
        hasBillingIssue: map['hasBillingIssue'] == true,
        unsubscribeDetected: map['unsubscribeDetected'] == true,
        managementUrl: map['managementUrl'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(SubscriptionStatus status) {
    final map = <String, dynamic>{
      'entitlement': status.entitlement.name,
      'activePlan': status.activePlan?.name,
      'willRenew': status.willRenew,
      'expiresAt': status.expiresAt?.millisecondsSinceEpoch,
      'store': status.store.name,
      'isSandbox': status.isSandbox,
      'hasBillingIssue': status.hasBillingIssue,
      'unsubscribeDetected': status.unsubscribeDetected,
      'managementUrl': status.managementUrl,
    };
    return _store.setSubscriptionCacheJson(jsonEncode(map));
  }

  static DateTime? _dateFromMillis(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  static T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
