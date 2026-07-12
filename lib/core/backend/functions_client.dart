import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/application/auth_service.dart' show firebaseReadyProvider;

/// The region the Cloud Functions are deployed to (mirrors `REGION` in
/// `functions/src/config.ts`).
const String kFunctionsRegion = 'us-central1';

/// A backend error surfaced to the AI services, carrying a user-safe [message]
/// and a [code] so callers can distinguish quota/auth/offline from a hard
/// failure. Keeps the `cloud_functions` `FirebaseFunctionsException` type
/// quarantined behind [callFunction].
class BackendException implements Exception {
  const BackendException(this.message, {this.code = 'internal', this.details});

  final String message;
  final String code;

  /// Structured error payload from the server (an `HttpsError`'s `details`).
  final Map<String, dynamic>? details;

  bool get isUnauthenticated => code == 'unauthenticated';

  /// A per-user RATE limit ("you're going too fast — wait a moment"), the
  /// server's abuse backstop (spec §10). Distinct from the free-tier quota even
  /// though both use `resource-exhausted`: a rate limit is transient and must
  /// NOT route to the paywall (upgrading doesn't lift a burst limit).
  bool get isRateLimited =>
      code == 'resource-exhausted' && details?['rateLimited'] == true;

  /// The free-tier allowance is spent → route to the paywall. Excludes a rate
  /// limit so a throttled user is never wrongly asked to pay.
  bool get isQuotaExceeded =>
      code == 'resource-exhausted' && !isRateLimited;

  bool get isOffline => code == 'unavailable' || code == 'deadline-exceeded';

  @override
  String toString() => 'BackendException($code: $message)';
}

/// The regional [FirebaseFunctions] instance. Only constructed when Firebase is
/// ready (the AI service providers gate on [aiBackendReadyProvider]), so this is
/// never touched on an unconfigured checkout / in tests.
final Provider<FirebaseFunctions> firebaseFunctionsProvider =
    Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: kFunctionsRegion),
);

/// Whether the real AI backend can be used: Firebase must be initialized AND the
/// user signed into a real (non-guest) account — the callables require an auth
/// token (`requireUid`). Guests and the unconfigured checkout fall back to the
/// on-device mock services, so the app stays fully usable.
final Provider<bool> aiBackendReadyProvider = Provider<bool>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return false;
  final user = ref.watch(currentUserProvider);
  return user != null && !user.isGuest;
});

/// Invokes a callable [name] with [data] and returns its `Map` result, mapping
/// every failure onto a typed [BackendException]. The single choke point where
/// the SDK exception type is translated.
Future<Map<String, dynamic>> callFunction(
  FirebaseFunctions functions,
  String name,
  Map<String, dynamic> data,
) async {
  try {
    final result = await functions.httpsCallable(name).call(data);
    final value = result.data;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const BackendException('Unexpected response from the server.');
  } on FirebaseFunctionsException catch (error) {
    final rawDetails = error.details;
    throw BackendException(
      error.message ?? 'Something went wrong. Please try again.',
      code: error.code,
      details: rawDetails is Map
          ? Map<String, dynamic>.from(rawDetails)
          : null,
    );
  }
}
