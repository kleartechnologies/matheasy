import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/persistence/preferences_store.dart';
import 'core/utils/app_logger.dart';
import 'features/auth/application/auth_service.dart';
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

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        AppLogger.error(
          'FlutterError',
          error: details.exception,
          stackTrace: details.stack,
        );
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        AppLogger.error('PlatformDispatcher', error: error, stackTrace: stack);
        return true;
      };

      final preferences = await SharedPreferences.getInstance();
      final firebaseReady = await _initializeFirebase();

      runApp(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(preferences),
            firebaseReadyProvider.overrideWithValue(firebaseReady),
          ],
          child: const MatheasyApp(),
        ),
      );
    },
    (error, stack) =>
        AppLogger.error('Uncaught zone error', error: error, stackTrace: stack),
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
    AppLogger.info(
      'Firebase not configured (placeholder config) — cloud sign-in disabled, '
      'guest mode only. Run: flutterfire configure --project=matheasy-873e2',
    );
    return false;
  }
  try {
    await Firebase.initializeApp(options: options);
    return true;
  } catch (error, stack) {
    AppLogger.error(
      'Firebase initialization failed — falling back to guest-only mode',
      error: error,
      stackTrace: stack,
    );
    return false;
  }
}
