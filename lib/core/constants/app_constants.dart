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

  // Support & legal. These are shown in-app AND submitted as store metadata, so
  // every one of them must resolve before review — a dead privacy URL is a
  // rejection on both stores. The domain is getmatheasy.com (matheasy.app was
  // never registered). Verified live 2026-08-04; the canonical host is `www.`
  // (the apex 308-redirects there, so link www directly and skip the hop).
  static const String supportEmail = 'support@getmatheasy.com';
  static const String privacyUrl = 'https://www.getmatheasy.com/privacy';
  static const String termsUrl = 'https://www.getmatheasy.com/terms';

  // NOT LIVE — /help still 404s. Deliberately unreferenced: wire it into a
  // screen only once the page exists, or review will follow it into a dead end.
  static const String helpCenterUrl = 'https://www.getmatheasy.com/help';

  // Store / marketing
  static const String appStoreUrl = 'https://apps.apple.com/app/matheasy';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.matheasy.matheasy';

  // Product limits (free tier) — surfaced by the paywall in later stages.
  static const int freeDailyScans = 3;
  static const int freeDailyTutorMessages = 10;

  // Layout invariants shared across screens.
  static const double phoneMaxContentWidth = 480;
}
