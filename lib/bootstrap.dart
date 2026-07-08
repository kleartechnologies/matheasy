import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/monitoring/crash_reporting_service.dart';
import 'core/monitoring/logging_service.dart';
import 'core/persistence/preferences_store.dart';
import 'features/analytics/application/analytics_service.dart';
import 'features/auth/application/auth_service.dart';
import 'features/subscription/application/revenuecat_bootstrap.dart';
import 'features/subscription/application/subscription_service.dart';
import 'features/sync/application/cloud_store.dart';
import 'firebase_options.dart';

/// Boots the app inside a guarded zone with centralized error handling.
///
/// Loads local preferences and initializes Firebase up front, then injects both
/// results into the [ProviderScope] so the rest of the app reads them
/// synchronously. If Firebase isn't configured yet (placeholder config) the app
/// still boots fully — into a guest-capable, cloud-sign-in-disabled mode.
Future<void> bootstrap() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Route every uncaught error to crash reporting. These read the global
      // CrashReporting.instance at call time, so they pick up the real reporter
      // once Firebase is initialized below (a no-op before that / in debug).
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        // Framework errors are recorded as non-fatal (they rarely crash).
        CrashReporting.instance.recordFlutterError(details);
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        CrashReporting.instance.recordError(error, stack, fatal: true);
        return true;
      };

      final preferences = await SharedPreferences.getInstance();
      final firebaseReady = await _initializeFirebase();
      final revenueCatReady = await initializeRevenueCat();

      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            firebaseReadyProvider.overrideWithValue(firebaseReady),
            revenueCatReadyProvider.overrideWithValue(revenueCatReady),
          ],
          child: const MatheasyApp(),
        ),
      );
    },
    (error, stack) =>
        CrashReporting.instance.recordError(error, stack, fatal: true),
  );
}

/// Initializes Firebase, returning whether cloud auth is available.
///
/// Detects the checked-in placeholder config by its sentinel apiKey so a fresh
/// checkout boots into guest-only mode instead of failing. This check keeps
/// working after `flutterfire configure` regenerates `firebase_options.dart`
/// with real values (the real apiKey won't carry the sentinel prefix).
Future<bool> _initializeFirebase() async {
  final options = DefaultFirebaseOptions.currentPlatform;
  if (options.apiKey.startsWith('REPLACE_')) {
    LoggingService.info(
      'Firebase not configured (placeholder config) — cloud sign-in disabled, '
      'guest mode only. Run: flutterfire configure --project=matheasy-873e2',
    );
    return false;
  }
  try {
    await Firebase.initializeApp(options: options);
    // Cloud data layer uses the local store as source of truth, so disable
    // Firestore's own offline cache for explicit sync control.
    configureFirestore();
    // Wire crash reporting + analytics (collection enabled only in release).
    CrashReporting.instance = await FirebaseCrashReportingService.initialize();
    Analytics.instance = await FirebaseAnalyticsService.initialize();
    return true;
  } catch (error, stack) {
    LoggingService.error(
      'Firebase initialization failed — falling back to guest-only mode',
      error: error,
      stackTrace: stack,
    );
    return false;
  }
}
