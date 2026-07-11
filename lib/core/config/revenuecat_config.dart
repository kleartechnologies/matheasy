import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Static RevenueCat wiring — API keys, the entitlement id and product ids.
///
/// The keys ship as `REPLACE_` placeholders, exactly like the checked-in
/// Firebase config: a fresh checkout still boots (into the offline/unconfigured
/// subscription fallback) and drops into real RevenueCat the moment real keys
/// are pasted in. Detection is by the sentinel prefix, so it keeps working after
/// the real keys land.
///
/// Product & entitlement identifiers are the Stage 11 contract:
/// * entitlement — `pro`
/// * products    — `matheasy_pro_monthly`, `matheasy_pro_annual`
class RevenueCatConfig {
  const RevenueCatConfig._();

  /// Public SDK key for the Apple App Store (starts with `appl_`). This is a
  /// PUBLIC key — safe to ship in the binary (unlike the RevenueCat secret /
  /// App Store Connect keys, which stay server-side).
  static const String appleApiKey = 'appl_vSSJZftjytGbgtEAuCghBIuYNXh';

  /// Public SDK key for Google Play (starts with `goog_`). Still a placeholder
  /// — the app runs the offline subscription fallback on Android until a Play
  /// app + key are set up in RevenueCat.
  static const String googleApiKey = 'REPLACE_WITH_REVENUECAT_GOOGLE_KEY';

  /// The entitlement identifier configured in the RevenueCat dashboard.
  static const String entitlementId = 'pro';

  static const String monthlyProductId = 'matheasy_pro_monthly';
  static const String annualProductId = 'matheasy_pro_annual';

  static const String _sentinelPrefix = 'REPLACE_';

  /// The API key for the current platform, or `null` on unsupported platforms
  /// (web/desktop) where in-app purchases aren't offered.
  static String? apiKeyForPlatform() {
    if (kIsWeb) return null;
    if (Platform.isIOS || Platform.isMacOS) return appleApiKey;
    if (Platform.isAndroid) return googleApiKey;
    return null;
  }

  /// Whether a real (non-placeholder) key is present for this platform, i.e.
  /// whether real RevenueCat should be initialized. When false, the app uses the
  /// local subscription fallback and stays fully usable.
  static bool get isConfigured {
    final key = apiKeyForPlatform();
    return key != null && key.isNotEmpty && !key.startsWith(_sentinelPrefix);
  }
}
