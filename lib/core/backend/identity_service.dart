import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/subscription/domain/server_usage.dart';
import '../security/installation_identity.dart';
import '../utils/app_logger.dart';
import 'functions_client.dart';

/// The client half of the server-side identity chain: the three callables the
/// app makes about WHO it is, as opposed to what it wants solved.
///
///   * [registerInstallation] — "this copy of the app, holding this account, is
///     here". Sent on every cold start; it is what makes a later account switch
///     on the same device visible to the server.
///   * [linkIdentity] — "the anonymous session you knew is now this account".
///     Sent immediately after an interactive sign-in so anonymous usage is
///     absorbed rather than abandoned.
///   * [fetchUsageStatus] — the meter. Read-only and advisory; the real decision
///     is re-made server-side on the next metered request.
///
/// Every method is best-effort and returns rather than throws. None of them is
/// on the path of anything the user asked for: a failed registration costs the
/// server some monitoring fidelity, and a failed status fetch costs the meter
/// its freshness. Neither is worth a visible error, and neither weakens
/// enforcement — the guard reads the database, not this call.
class IdentityService {
  const IdentityService(this._functions);

  final FirebaseFunctions _functions;

  /// Announces this installation under the currently signed-in (possibly
  /// anonymous) account. No-op without an installation id.
  Future<void> registerInstallation() async {
    final id = InstallationIdentity.value;
    if (id == null) return;
    await _quietly(
      'registerInstallation',
      () => callFunction(
        _functions,
        'registerInstallation',
        <String, dynamic>{'installationId': id},
      ),
    );
  }

  /// Binds the just-signed-in account to this installation and folds
  /// [previousUid]'s usage into it.
  ///
  /// [previousUid] is the anonymous uid the device held a moment ago. It is
  /// safe to send unproven: a merge takes the MAXIMUM of the two ledgers, so
  /// there is no value of it that increases anyone's allowance.
  Future<void> linkIdentity({String? previousUid}) async {
    final id = InstallationIdentity.value;
    if (id == null && previousUid == null) return;
    await _quietly(
      'linkIdentity',
      () => callFunction(_functions, 'linkIdentity', <String, dynamic>{
        'installationId': ?id,
        'previousUid': ?previousUid,
      }),
    );
  }

  /// Fetches the authoritative meter, or `null` if it could not be read.
  Future<ServerUsage?> fetchUsageStatus() async {
    final result = await _quietly(
      'usageStatus',
      () => callFunction(_functions, 'usageStatus', const <String, dynamic>{}),
    );
    if (result == null) return null;
    try {
      return ServerUsage.fromJson(result);
    } catch (error, stack) {
      AppLogger.error(
        'usageStatus returned an unreadable payload',
        error: error,
        stackTrace: stack,
      );
      return null;
    }
  }

  /// Runs [action], swallowing every failure into a log line.
  ///
  /// Deliberately total: an offline launch, a cold-start timeout and a rejected
  /// token all look the same here, because the response to all three is the
  /// same — carry on, and try again next launch.
  Future<Map<String, dynamic>?> _quietly(
    String name,
    Future<Map<String, dynamic>> Function() action,
  ) async {
    try {
      return await action();
    } catch (error) {
      AppLogger.info('$name skipped: $error');
      return null;
    }
  }
}

/// Provides the [IdentityService]. Only read once Firebase is ready — it
/// constructs the regional [FirebaseFunctions] instance.
final Provider<IdentityService> identityServiceProvider =
    Provider<IdentityService>(
  (ref) => IdentityService(ref.watch(firebaseFunctionsProvider)),
);
