import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/app_localizations_en.dart';

/// Ergonomic access to the generated [AppLocalizations] from any widget:
/// `context.l10n.navHome`. Strings resolve to the learner's selected language
/// (MaterialApp.locale follows the setting), falling back to English for any key
/// not yet translated.
///
/// Falls back to an English instance when the localization delegate isn't in the
/// tree — i.e. widget tests that pump a bare `MaterialApp` — so rewiring a string
/// to `context.l10n` never crashes a test and English-label assertions still hold.
extension L10nExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this) ?? AppLocalizationsEn();
}
