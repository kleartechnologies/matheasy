import 'package:firebase_app_installations/firebase_app_installations.dart';

import '../utils/app_logger.dart';

/// Layer 1 of the identity chain: this **installation** of the app.
///
/// The value is the Firebase Installation ID (FID) — an id Firebase mints per
/// app-install, scoped to this app on this device. It is deliberately the *only*
/// device-linked identifier Matheasy touches:
///
///   * NOT the IMEI, MAC address, serial number or advertising id. Those are
///     prohibited or restricted by the App Store, Play and GDPR, and none of
///     them is used, read, or derived from here.
///   * It is resettable — deleting the app or the installation issues a new one.
///     That is a feature, not a hole: it is the user's privacy escape hatch, and
///     the cost of using it is bounded by the account layer above.
///
/// It is a **hint**, not a credential. The server treats it as a lookup key and
/// stores only its SHA-256, so a forged or missing value can never *raise* an
/// allowance — the worst it does is fail to find this device's ledger, leaving
/// the account ledger (which the client cannot reach) to do the enforcing. See
/// `functions/src/identity/installations.ts` and
/// `docs/matheasy-anti-abuse-security.md`.
///
/// Read synchronously through [value] from the Cloud Functions call sites, which
/// is why the resolved id is cached in a static: the FID is fetched once during
/// [initialize] at boot and every later call is a field read.
class InstallationIdentity {
  const InstallationIdentity._();

  static String? _value;

  /// The cached installation id, or `null` before [initialize] has resolved one
  /// (unconfigured checkout, tests, or a failed fetch). Callers must treat
  /// `null` as "don't send the field" — never as an error.
  static String? get value => _value;

  /// Fetches and caches the FID. Safe to call more than once; returns the cached
  /// value on a second call.
  ///
  /// Never throws: identity is best-effort on the client precisely because it is
  /// authoritative on the server. A device that cannot produce an installation
  /// id still gets metered — just on its account ledger alone.
  static Future<String?> initialize() async {
    if (_value != null) return _value;
    try {
      final id = await FirebaseInstallations.instance.getId();
      if (id.trim().isEmpty) return null;
      return _value = id.trim();
    } catch (error, stack) {
      AppLogger.error(
        'Installation id unavailable — metering falls back to the account '
        'ledger alone',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Overrides the cached id. Tests only — production code has exactly one
  /// writer, [initialize].
  static void debugSet(String? id) => _value = id;
}
