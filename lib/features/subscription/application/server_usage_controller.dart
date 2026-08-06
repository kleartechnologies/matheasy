import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/backend/identity_service.dart';
import '../../../core/persistence/preferences_store.dart';
import '../../progress/application/achievement_service.dart' show clockProvider;
import '../domain/server_usage.dart';

part 'server_usage_controller.g.dart';

/// Holds the server's authoritative meter, or `null` before one has been read.
///
/// The local [UsageController] keeps counting optimistically — it is what makes
/// the meter move the instant a scan completes, offline included. This provider
/// is the correction on top of it: the number the server will actually enforce,
/// fetched at launch and after every sign-in.
///
/// The two are folded together in `usageSnapshotProvider` by taking the larger
/// of each counter, which is what makes a wiped preferences file, a reinstall or
/// a brand-new Google account show the usage the server already remembers
/// instead of a hopeful zero.
///
/// Nothing here decides anything. `usage/guard.ts` does, from the database, on
/// every metered request.
@Riverpod(keepAlive: true)
class ServerUsageController extends _$ServerUsageController {
  @override
  ServerUsage? build() => null;

  /// Pulls a fresh meter. Silent on failure — a stale meter is a cosmetic
  /// problem, and the previous value is a better guess than nothing.
  Future<void> refresh() async {
    if (!ref.read(aiBackendReadyProvider)) return;
    final usage = await ref.read(identityServiceProvider).fetchUsageStatus();
    if (usage != null) {
      state = usage;
      // Remember how far this device's clock sits from the server's, for the
      // trusted clock that keeps daily-challenge day-keys honest (see
      // `trustedClockProvider`). Best-effort: a missed write means the clock
      // is trusted as-is, exactly as before this signal existed.
      final serverNowMs = usage.serverNowMs;
      if (serverNowMs != null) {
        final deviceNowMs = ref.read(clockProvider)().millisecondsSinceEpoch;
        unawaited(ref
            .read(preferencesStoreProvider)
            .setServerClockOffsetMs(serverNowMs - deviceNowMs));
      }
    }
  }

  /// Drops the cached meter — on sign-out, so the next account is not shown the
  /// previous one's numbers before its own arrive.
  void clear() => state = null;
}
