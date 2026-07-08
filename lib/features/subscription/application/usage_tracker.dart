import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/persistence/preferences_store.dart';
import '../domain/usage_counts.dart';

/// The persistence seam for the [UsageCounts] ledger. The controller depends
/// only on this interface, so the backing store can be swapped (a test fake, a
/// future cloud sync) without touching it. Mirrors `SettingsRepository`.
abstract interface class UsageTracker {
  /// Loads persisted counts, or [UsageCounts.empty] when none exist.
  UsageCounts load();

  /// Persists the full counts payload.
  Future<void> save(UsageCounts counts);
}

/// Provides the active [UsageTracker], backed by the local key-value store.
final Provider<UsageTracker> usageTrackerProvider = Provider<UsageTracker>(
  (ref) => LocalUsageTracker(ref.watch(preferencesStoreProvider)),
);

/// A [UsageTracker] that serializes [UsageCounts] to a single JSON blob in
/// [PreferencesStore]. A corrupt payload degrades to [UsageCounts.empty].
class LocalUsageTracker implements UsageTracker {
  const LocalUsageTracker(this._prefs);

  final PreferencesStore _prefs;

  @override
  UsageCounts load() {
    final raw = _prefs.usageCountsJson;
    if (raw == null || raw.isEmpty) return UsageCounts.empty;
    try {
      return UsageCounts.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return UsageCounts.empty;
    }
  }

  @override
  Future<void> save(UsageCounts counts) =>
      _prefs.setUsageCountsJson(jsonEncode(counts.toJson()));
}
