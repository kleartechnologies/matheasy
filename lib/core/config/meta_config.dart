/// Static Meta (Facebook) Ads wiring — the App ID and Client Token that gate
/// whether the Facebook SDK is activated for install/event attribution.
///
/// These ship as `REPLACE_` placeholders, exactly like [RevenueCatConfig] and
/// the checked-in Firebase config: a fresh checkout still builds and runs
/// (Meta stays fully dormant — no SDK calls, no ATT prompt, no events), and it
/// drops into real Meta attribution the moment real values are pasted in.
/// Detection is by the sentinel prefix, so it keeps working after the real
/// values land.
///
/// IMPORTANT: the native Facebook SDK reads the App ID + Client Token from the
/// platform config, NOT from here — so the SAME two values must also be set in:
///   * iOS   — `ios/Runner/Info.plist` (`FacebookAppID`, `FacebookClientToken`)
///   * Android — `android/app/src/main/res/values/strings.xml`
///     (`facebook_app_id`, `facebook_client_token`)
/// This class is only the runtime GATE (does the app touch the SDK at all).
class MetaConfig {
  const MetaConfig._();

  /// The Meta App ID from Meta for Developers → App → Settings → Basic. Numeric,
  /// and safe to ship in the binary (it is public, like the RevenueCat SDK key).
  static const String appId = 'REPLACE_WITH_META_APP_ID';

  /// The Meta Client Token from App → Settings → Advanced → Client Token. Public
  /// (client-side) token — NOT the App Secret, which must never ship in the app.
  static const String clientToken = 'REPLACE_WITH_META_CLIENT_TOKEN';

  /// The name shown as the Facebook display name (`FacebookDisplayName`).
  static const String displayName = 'Matheasy';

  static const String _sentinelPrefix = 'REPLACE_';

  /// Whether real (non-placeholder) Meta credentials are present, i.e. whether
  /// the Facebook SDK should be activated. When false the whole Meta layer is a
  /// no-op and the app is unaffected.
  static bool get isConfigured =>
      appId.isNotEmpty &&
      clientToken.isNotEmpty &&
      !appId.startsWith(_sentinelPrefix) &&
      !clientToken.startsWith(_sentinelPrefix);
}
