import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/monitoring/crash_reporting_service.dart';
import '../../../core/session/app_session.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_service.dart' show firebaseReadyProvider;
import '../../subscription/application/subscription_controller.dart';
import '../../subscription/application/subscription_service.dart';
import '../../sync/application/sync_controller.dart';
import '../../sync/domain/sync_status.dart';
import '../domain/app_health_report.dart';
import '../domain/diagnostic_status.dart';

part 'diagnostics_service.g.dart';

/// Builds the developer [AppHealthReport] from raw subsystem state. Pure and
/// static so it's trivially unit-testable; the reactive [appHealthReportProvider]
/// feeds it live provider values.
class DiagnosticsService {
  const DiagnosticsService._();

  static AppHealthReport build({
    required bool firebaseReady,
    required bool revenueCatReady,
    required bool isPro,
    required SyncStatus syncStatus,
    required AuthStatus authStatus,
    required bool isGuest,
    required bool crashlyticsEnabled,
  }) {
    return AppHealthReport(
      appVersion: AppConstants.appVersion,
      buildNumber: AppConstants.appBuildNumber,
      buildMode: kReleaseMode
          ? 'release'
          : kProfileMode
              ? 'profile'
              : 'debug',
      subsystems: [
        DiagnosticEntry(
          label: 'Firebase',
          status: firebaseReady ? DiagnosticStatus.ok : DiagnosticStatus.disabled,
          detail: firebaseReady ? 'Initialized' : 'Not configured (placeholder)',
        ),
        DiagnosticEntry(
          label: 'Auth',
          status: switch (authStatus) {
            AuthStatus.authenticated => DiagnosticStatus.ok,
            AuthStatus.unauthenticated => DiagnosticStatus.degraded,
            AuthStatus.unknown => DiagnosticStatus.unknown,
          },
          detail: switch (authStatus) {
            AuthStatus.authenticated => isGuest ? 'Guest' : 'Signed in',
            AuthStatus.unauthenticated => 'Signed out',
            AuthStatus.unknown => 'Resolving…',
          },
        ),
        DiagnosticEntry(
          label: 'RevenueCat',
          status:
              revenueCatReady ? DiagnosticStatus.ok : DiagnosticStatus.disabled,
          detail: revenueCatReady
              ? (isPro ? 'Pro' : 'Free')
              : 'Not configured (offline fallback)',
        ),
        DiagnosticEntry(
          label: 'Cloud sync',
          status: switch (syncStatus) {
            SyncStatus.synced || SyncStatus.syncing => DiagnosticStatus.ok,
            SyncStatus.offline => DiagnosticStatus.degraded,
            SyncStatus.error => DiagnosticStatus.down,
            SyncStatus.disabled => DiagnosticStatus.disabled,
            SyncStatus.notSynced => DiagnosticStatus.unknown,
          },
          detail: syncStatus.name,
        ),
        DiagnosticEntry(
          label: 'Crashlytics',
          status: crashlyticsEnabled
              ? DiagnosticStatus.ok
              : DiagnosticStatus.disabled,
          detail: crashlyticsEnabled ? 'Collecting' : 'Off (debug / unconfigured)',
        ),
        DiagnosticEntry(
          label: 'Analytics',
          status:
              firebaseReady ? DiagnosticStatus.ok : DiagnosticStatus.disabled,
          detail: firebaseReady
              ? 'Release-only collection'
              : 'Off (unconfigured)',
        ),
      ],
    );
  }
}

/// Live app-health snapshot for the diagnostics screen. Reacts to every
/// subsystem it reports on.
@riverpod
AppHealthReport appHealthReport(Ref ref) {
  final user = ref.watch(currentUserProvider);
  return DiagnosticsService.build(
    firebaseReady: ref.watch(firebaseReadyProvider),
    revenueCatReady: ref.watch(revenueCatReadyProvider),
    isPro: ref.watch(subscriptionControllerProvider).isPro,
    syncStatus: ref.watch(syncControllerProvider).status,
    authStatus: ref.watch(authStatusProvider),
    isGuest: user?.isGuest ?? false,
    crashlyticsEnabled: ref.watch(crashReportingServiceProvider).isEnabled,
  );
}
