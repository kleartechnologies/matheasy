import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/config/meta_config.dart';
import '../../../core/persistence/preferences_store.dart';
import '../domain/age_assurance.dart';
import 'meta_analytics_service.dart';

part 'age_gate_controller.g.dart';

/// The COPPA age gate for ad tracking. Reads the persisted birth year, classifies
/// the user, and drives [MetaSdk.trackingAllowed] — the single flag every Meta
/// code path checks. Kept alive so the decision survives navigation.
///
/// Fails closed: an unknown age keeps tracking OFF, so no ad data reaches Meta
/// until a 13+ user is confirmed.
@Riverpod(keepAlive: true)
class AgeGateController extends _$AgeGateController {
  PreferencesStore get _prefs => ref.read(preferencesStoreProvider);

  @override
  AgeAssurance build() => _applyToGate();

  AgeAssurance _applyToGate() {
    final assurance = assuranceForBirthYear(
      _prefs.birthYear,
      currentYear: DateTime.now().year,
    );
    MetaSdk.trackingAllowed = assurance.adTrackingPermitted;
    return assurance;
  }

  /// Whether the neutral age prompt should be shown: Meta is configured, the age
  /// is still unknown, and we haven't already recorded an answer.
  ///
  /// Gated on [MetaConfig.isConfigured] — a compile-time constant — and NOT on
  /// [MetaSdk.isReady]. `isReady` is false in debug/profile and after any
  /// Facebook-SDK init failure, which used to mean the whole consent chain
  /// (age gate → ATT) silently never ran, with no way to tell from the outside.
  /// App Review guideline 2.1 requires the ATT request to actually appear, so
  /// the prompt must not hinge on a runtime SDK handle.
  bool get shouldPrompt =>
      MetaConfig.isConfigured &&
      state == AgeAssurance.unknown &&
      !_prefs.adConsentPrompted;

  /// Records the declared birth year, marks the prompt answered, and updates the
  /// tracking gate.
  Future<void> recordBirthYear(int year) async {
    await _prefs.setBirthYear(year);
    await _prefs.setAdConsentPrompted();
    state = _applyToGate();
  }

  /// Marks the prompt shown without an answer. Reserved for a genuine teardown
  /// (the dialog's route is disposed out from under it); the dialog itself is
  /// no longer dismissible, so an unanswered prompt is re-asked next launch
  /// rather than stranding the user before the ATT request.
  Future<void> markPromptedWithoutAnswer() => _prefs.setAdConsentPrompted();
}
