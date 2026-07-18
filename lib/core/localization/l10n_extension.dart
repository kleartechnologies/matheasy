import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';

/// Ergonomic access to the generated [AppLocalizations] from any widget:
/// `context.l10n.navHome`. The strings resolve to the learner's selected
/// language (MaterialApp.locale follows the setting), falling back to English
/// for any key not yet translated.
extension L10nExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
