import 'package:purchases_flutter/purchases_flutter.dart';

import '../../../core/config/revenuecat_config.dart';
import '../../../core/utils/app_logger.dart';

/// One-time RevenueCat SDK initialization, called from `bootstrap` before the
/// app runs. Returns whether the SDK configured successfully — the result is
/// injected via `revenueCatReadyProvider` to pick the real vs. offline service.
///
/// Keeps the `Purchases.configure` call (and the SDK import) inside the
/// subscription feature, so `bootstrap` stays free of `purchases_flutter`,
/// mirroring how Firebase init is quarantined.
///
/// With placeholder API keys (a fresh checkout) this no-ops and returns `false`,
/// so the app boots into the fully-usable offline fallback.
Future<bool> initializeRevenueCat() async {
  if (!RevenueCatConfig.isConfigured) {
    AppLogger.info(
      'RevenueCat not configured (placeholder keys) — subscriptions run on the '
      'offline fallback. Paste real keys into RevenueCatConfig to enable it.',
    );
    return false;
  }
  final apiKey = RevenueCatConfig.apiKeyForPlatform();
  if (apiKey == null) return false;
  try {
    await Purchases.setLogLevel(LogLevel.info);
    await Purchases.configure(PurchasesConfiguration(apiKey));
    return true;
  } catch (error, stack) {
    AppLogger.error(
      'RevenueCat initialization failed — falling back to offline mode',
      error: error,
      stackTrace: stack,
    );
    return false;
  }
}
