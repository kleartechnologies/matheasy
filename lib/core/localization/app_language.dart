import 'package:flutter/widgets.dart';

/// A language the learner can choose. The selection controls the ENTIRE learning
/// experience — every AI-generated response (explanations, solution steps, Visual
/// captions, practice questions, the tutor, hints, errors) — while mathematical
/// notation stays universal.
///
/// The architecture supports unlimited languages: adding one is a value here (its
/// BCP-47 [code] + [promptName] + [nativeName]/[englishName] + [locale]) plus a
/// matching server `LANGUAGE_NAMES` entry keyed by [code]. A fully-translated app
/// UI additionally needs an `app_<code>.arb`; without one the app chrome falls
/// back to English while AI content is still generated in the chosen language.
enum AppLanguage {
  english('en', 'English', 'English', 'English', Locale('en')),
  arabic('ar', 'Arabic', 'العربية', 'Arabic', Locale('ar')),
  simplifiedChinese(
    'zh-Hans',
    'Simplified Chinese',
    '简体中文',
    'Chinese, Simplified',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ),
  traditionalChinese(
    'zh-Hant',
    'Traditional Chinese',
    '繁體中文',
    'Chinese, Traditional',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ),
  croatian('hr', 'Croatian', 'Hrvatski', 'Croatian', Locale('hr')),
  czech('cs', 'Czech', 'Čeština', 'Czech', Locale('cs')),
  danish('da', 'Danish', 'Dansk', 'Danish', Locale('da')),
  dutch('nl', 'Dutch', 'Nederlands', 'Dutch', Locale('nl')),
  finnish('fi', 'Finnish', 'Suomi', 'Finnish', Locale('fi')),
  french('fr', 'French', 'Français', 'French', Locale('fr')),
  german('de', 'German', 'Deutsch', 'German', Locale('de')),
  hebrew('he', 'Hebrew', 'עברית', 'Hebrew', Locale('he')),
  hindi('hi', 'Hindi', 'हिन्दी', 'Hindi', Locale('hi')),
  hungarian('hu', 'Hungarian', 'Magyar', 'Hungarian', Locale('hu')),
  indonesian(
    'id-ID',
    'Bahasa Indonesia',
    'Bahasa Indonesia',
    'Indonesian',
    Locale('id'),
  ),
  italian('it', 'Italian', 'Italiano', 'Italian', Locale('it')),
  japanese('ja', 'Japanese', '日本語', 'Japanese', Locale('ja')),
  korean('ko', 'Korean', '한국어', 'Korean', Locale('ko')),
  malay('ms-MY', 'Bahasa Melayu', 'Bahasa Melayu', 'Malay', Locale('ms')),
  norwegianBokmal(
    'nb',
    'Norwegian Bokmål',
    'Norsk Bokmål',
    'Norwegian Bokmål',
    Locale('nb'),
  ),
  persian('fa', 'Persian', 'فارسی', 'Persian', Locale('fa')),
  polish('pl', 'Polish', 'Polski', 'Polish', Locale('pl')),
  portuguese('pt', 'Portuguese', 'Português', 'Portuguese', Locale('pt')),
  romanian('ro', 'Romanian', 'Română', 'Romanian', Locale('ro')),
  russian('ru', 'Russian', 'Русский', 'Russian', Locale('ru')),
  slovak('sk', 'Slovak', 'Slovenčina', 'Slovak', Locale('sk')),
  spanish('es', 'Spanish', 'Español', 'Spanish', Locale('es')),
  swedish('sv', 'Swedish', 'Svenska', 'Swedish', Locale('sv')),
  thai('th', 'Thai', 'ไทย', 'Thai', Locale('th')),
  turkish('tr', 'Turkish', 'Türkçe', 'Turkish', Locale('tr')),
  ukrainian('uk', 'Ukrainian', 'Українська', 'Ukrainian', Locale('uk')),
  vietnamese('vi', 'Vietnamese', 'Tiếng Việt', 'Vietnamese', Locale('vi'));

  const AppLanguage(
    this.code,
    this.promptName,
    this.nativeName,
    this.englishName,
    this.locale,
  );

  /// BCP-47 tag sent to the backend and used as the AI language/cache key
  /// (e.g. `ms-MY`, `zh-Hans`, `fr`). This is what every AI request carries and
  /// the key the server `LANGUAGE_NAMES` map must match.
  final String code;

  /// The language name the LLM is instructed to write in — the plain, endonym-
  /// agnostic label (e.g. "Bahasa Melayu", "Simplified Chinese", "French").
  final String promptName;

  /// The endonym shown as the primary label in the language picker
  /// (e.g. "简体中文", "한국어", "Français").
  final String nativeName;

  /// The English name shown as the picker's secondary line beneath [nativeName]
  /// (e.g. "Chinese, Simplified", "Korean", "French").
  final String englishName;

  /// The Flutter [Locale] used for UI localization + `MaterialApp.locale`.
  final Locale locale;

  /// Whether this is the default, notation-only baseline (no translation needed).
  bool get isEnglish => this == AppLanguage.english;

  /// Resolves a stored [code] back to a language, defaulting to [english].
  static AppLanguage fromCode(String? code) => values.firstWhere(
        (l) => l.code == code,
        orElse: () => AppLanguage.english,
      );

  /// The best match for a device [locale] (language+script, then language), or
  /// [english] when nothing matches — used to seed the default on first run.
  static AppLanguage fromLocale(Locale locale) {
    for (final l in values) {
      if (l.locale.languageCode == locale.languageCode &&
          l.locale.scriptCode == locale.scriptCode) {
        return l;
      }
    }
    for (final l in values) {
      if (l.locale.languageCode == locale.languageCode) return l;
    }
    return AppLanguage.english;
  }
}
