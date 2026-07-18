import 'package:flutter/widgets.dart';

/// A language the learner can choose. The selection controls the ENTIRE learning
/// experience — the UI *and* every AI-generated response (explanations, solution
/// steps, Visual captions, practice questions, the tutor, hints, errors) — while
/// mathematical notation stays universal.
///
/// The architecture supports unlimited future languages: adding one is a value
/// here (with its BCP-47 [code] + [promptName] + a `.arb`); everything else — the
/// UI locale, the AI language directive, the picker — derives from this list.
enum AppLanguage {
  english('en', 'English', 'English', Locale('en')),
  malay('ms-MY', 'Bahasa Melayu', 'Bahasa Melayu', Locale('ms')),
  indonesian('id-ID', 'Bahasa Indonesia', 'Bahasa Indonesia', Locale('id')),
  simplifiedChinese(
    'zh-Hans',
    'Simplified Chinese',
    '简体中文',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  ),
  traditionalChinese(
    'zh-Hant',
    'Traditional Chinese',
    '繁體中文',
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ),
  hindi('hi', 'Hindi', 'हिन्दी', Locale('hi')),
  japanese('ja', 'Japanese', '日本語', Locale('ja')),
  korean('ko', 'Korean', '한국어', Locale('ko'));

  const AppLanguage(this.code, this.promptName, this.nativeName, this.locale);

  /// BCP-47 tag sent to the backend and used as the AI language/cache key
  /// (e.g. `ms-MY`, `zh-Hans`). This is what every AI request carries.
  final String code;

  /// The language name the LLM is instructed to write in — the plain English
  /// endonym-agnostic label (e.g. "Bahasa Melayu", "Simplified Chinese").
  final String promptName;

  /// The endonym shown in the language picker (e.g. "简体中文", "한국어").
  final String nativeName;

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
