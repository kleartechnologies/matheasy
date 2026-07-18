import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_language.dart';
import 'settings_controller.dart';

/// The learner's current language — the single authority for both the UI locale
/// and every AI request. Derived from the persisted setting, so changing the
/// language takes effect instantly (no restart): the UI re-localizes and every
/// subsequent backend call carries the new [AppLanguage.code].
final preferredLanguageProvider = Provider<AppLanguage>(
  (ref) => ref.watch(
    settingsControllerProvider.select((s) => s.learning.language),
  ),
);

/// The learner-profile fields every AI backend request carries (per the spec
/// contract): `language` (the AUTHORITY — every callable applies it) and
/// `gradeLevel` (carried on the contract; the practice path already tailors by
/// its own `grade`, other callables carry it for forward-use). Merged into the
/// payload centrally by each AI service's provider, so no call site can forget
/// it. `difficulty` is request-specific (the problem's / practice level).
final aiRequestContextProvider = Provider<Map<String, dynamic>>((ref) {
  final learning =
      ref.watch(settingsControllerProvider.select((s) => s.learning));
  return {
    'language': learning.language.code,
    if (learning.gradeLevel != null) 'gradeLevel': learning.gradeLevel!.label,
  };
});
