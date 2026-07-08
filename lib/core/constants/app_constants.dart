/// Global, environment-agnostic constants for the Matheasy app.
///
/// Keep this file free of any Flutter/UI imports so it can be used from any
/// layer (data, domain, presentation) without creating coupling.
class AppConstants {
  const AppConstants._();

  // Identity
  static const String appName = 'Matheasy';
  static const String appTagline = 'Make Math Easy';

  // Version — mirrors `version:` in pubspec.yaml (1.0.0+1). Kept here so the
  // About screen can display it without a platform plugin; update alongside the
  // pubspec on each release.
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';

  // Support & legal
  static const String supportEmail = 'support@matheasy.app';
  static const String privacyUrl = 'https://matheasy.app/privacy';
  static const String termsUrl = 'https://matheasy.app/terms';
  static const String helpCenterUrl = 'https://matheasy.app/help';

  // Store / marketing
  static const String appStoreUrl = 'https://apps.apple.com/app/matheasy';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.matheasy';

  // Product limits (free tier) — surfaced by the paywall in later stages.
  static const int freeDailyScans = 3;
  static const int freeDailyTutorMessages = 10;

  // Layout invariants shared across screens.
  static const double phoneMaxContentWidth = 480;
}
