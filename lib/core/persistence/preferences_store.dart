import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the loaded [SharedPreferences] instance.
///
/// Overridden in `bootstrap` (and in tests) with a concrete instance loaded up
/// front, so preference reads elsewhere can stay synchronous. Left unoverridden
/// it throws — a loud signal that setup is missing rather than silent bad data.
final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in bootstrap or tests.',
  ),
);

/// The app's local key-value store — the persistence foundation for session
/// flags (onboarding completed, guest mode). Cloud sync arrives in a later
/// stage; this stays the local source of truth.
final Provider<PreferencesStore> preferencesStoreProvider =
    Provider<PreferencesStore>(
  (ref) => PreferencesStore(ref.watch(sharedPreferencesProvider)),
);

/// A thin, typed wrapper over [SharedPreferences]. Keys are namespaced so the
/// store can grow without collisions.
class PreferencesStore {
  const PreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  static const String _kOnboardingComplete = 'session.onboarding_complete';
  static const String _kGuestMode = 'session.guest_mode';
  static const String _kPracticeProgress = 'practice.progress';
  static const String _kAchievements = 'progress.achievements';
  static const String _kProgressStats = 'progress.stats';
  static const String _kSettings = 'settings.preferences';
  static const String _kProfile = 'profile.editable';
  static const String _kUsageCounts = 'subscription.usage';
  static const String _kSubscriptionCache = 'subscription.cache';
  static const String _kLastPaywallImpression = 'subscription.last_paywall';
  static const String _kSyncMetadata = 'sync.metadata';
  static const String _kLastSynced = 'sync.last_synced';

  /// Whether the user has finished onboarding (so returning users skip it).
  bool get onboardingComplete =>
      _prefs.getBool(_kOnboardingComplete) ?? false;

  Future<void> setOnboardingComplete({required bool value}) =>
      _prefs.setBool(_kOnboardingComplete, value);

  /// Whether the user chose "Continue as Guest" (restored across launches).
  bool get guestMode => _prefs.getBool(_kGuestMode) ?? false;

  Future<void> setGuestMode({required bool value}) =>
      _prefs.setBool(_kGuestMode, value);

  /// Clears session-scoped flags (guest mode) on sign-out. Onboarding
  /// completion is intentionally preserved.
  Future<void> clearSession() => _prefs.remove(_kGuestMode);

  /// Wipes every on-device learning artifact — practice progress, achievements,
  /// analytics, settings and the editable profile. Used by "Delete Account" so a
  /// removed account leaves nothing behind. Session/onboarding flags are handled
  /// separately by the auth layer.
  Future<void> clearLearningData() async {
    await _prefs.remove(_kPracticeProgress);
    await _prefs.remove(_kAchievements);
    await _prefs.remove(_kProgressStats);
    await _prefs.remove(_kSettings);
    await _prefs.remove(_kProfile);
    await _prefs.remove(_kUsageCounts);
    await _prefs.remove(_kSubscriptionCache);
    await _prefs.remove(_kLastPaywallImpression);
    await _prefs.remove(_kSyncMetadata);
    await _prefs.remove(_kLastSynced);
  }

  /// The serialized practice progress (JSON), or `null` when none saved yet.
  String? get practiceProgressJson => _prefs.getString(_kPracticeProgress);

  Future<void> setPracticeProgressJson(String json) =>
      _prefs.setString(_kPracticeProgress, json);

  /// The serialized achievement unlocks (JSON).
  String? get achievementsJson => _prefs.getString(_kAchievements);

  Future<void> setAchievementsJson(String json) =>
      _prefs.setString(_kAchievements, json);

  /// The serialized progress analytics (JSON).
  String? get progressStatsJson => _prefs.getString(_kProgressStats);

  Future<void> setProgressStatsJson(String json) =>
      _prefs.setString(_kProgressStats, json);

  /// The serialized app settings — learning preferences, notifications,
  /// appearance and accessibility (JSON).
  String? get settingsJson => _prefs.getString(_kSettings);

  Future<void> setSettingsJson(String json) =>
      _prefs.setString(_kSettings, json);

  /// The serialized editable profile — display-name override and avatar (JSON).
  String? get profileJson => _prefs.getString(_kProfile);

  Future<void> setProfileJson(String json) => _prefs.setString(_kProfile, json);

  /// The serialized lifetime usage counters — scans, Numi messages and
  /// generated practice questions (JSON).
  String? get usageCountsJson => _prefs.getString(_kUsageCounts);

  Future<void> setUsageCountsJson(String json) =>
      _prefs.setString(_kUsageCounts, json);

  /// The cached [SubscriptionStatus] (JSON). RevenueCat is the source of truth;
  /// this is only a warm-start snapshot so the app opens with the last-known
  /// entitlement before the first refresh resolves.
  String? get subscriptionCacheJson => _prefs.getString(_kSubscriptionCache);

  Future<void> setSubscriptionCacheJson(String json) =>
      _prefs.setString(_kSubscriptionCache, json);

  /// Epoch millis of the last time the paywall was shown, or `null` if never.
  /// Used to avoid re-showing the paywall too eagerly within a session.
  int? get lastPaywallImpressionMillis =>
      _prefs.getInt(_kLastPaywallImpression);

  Future<void> setLastPaywallImpressionMillis(int millis) =>
      _prefs.setInt(_kLastPaywallImpression, millis);

  /// The serialized per-domain sync metadata (versions + timestamps) used for
  /// cloud conflict resolution (JSON).
  String? get syncMetadataJson => _prefs.getString(_kSyncMetadata);

  Future<void> setSyncMetadataJson(String json) =>
      _prefs.setString(_kSyncMetadata, json);

  /// Epoch millis of the last successful cloud sync, or `null` if never.
  int? get lastSyncedMillis => _prefs.getInt(_kLastSynced);

  Future<void> setLastSyncedMillis(int millis) =>
      _prefs.setInt(_kLastSynced, millis);
}
