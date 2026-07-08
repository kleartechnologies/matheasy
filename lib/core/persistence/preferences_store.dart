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
}
