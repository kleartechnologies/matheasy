import 'diagnostic_status.dart';

/// One subsystem row in the [AppHealthReport].
class DiagnosticEntry {
  const DiagnosticEntry({
    required this.label,
    required this.status,
    this.detail,
  });

  final String label;
  final DiagnosticStatus status;
  final String? detail;
}

/// A snapshot of app + backend health for the developer diagnostics screen
/// (non-production tooling only). Pure data — the service builds it from live
/// provider state, the screen renders it.
class AppHealthReport {
  const AppHealthReport({
    required this.subsystems,
    required this.appVersion,
    required this.buildNumber,
    required this.buildMode,
  });

  /// Firebase / RevenueCat / Sync / Auth / Crashlytics / Analytics rows.
  final List<DiagnosticEntry> subsystems;

  final String appVersion;
  final String buildNumber;

  /// `debug`, `profile`, or `release`.
  final String buildMode;

  /// Worst status across subsystems — the overall banner.
  DiagnosticStatus get overall {
    var worst = DiagnosticStatus.ok;
    for (final entry in subsystems) {
      if (entry.status.index > worst.index &&
          entry.status != DiagnosticStatus.disabled &&
          entry.status != DiagnosticStatus.unknown) {
        worst = entry.status;
      }
    }
    return worst;
  }
}
