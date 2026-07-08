// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diagnostics_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Live app-health snapshot for the diagnostics screen. Reacts to every
/// subsystem it reports on.

@ProviderFor(appHealthReport)
final appHealthReportProvider = AppHealthReportProvider._();

/// Live app-health snapshot for the diagnostics screen. Reacts to every
/// subsystem it reports on.

final class AppHealthReportProvider
    extends
        $FunctionalProvider<AppHealthReport, AppHealthReport, AppHealthReport>
    with $Provider<AppHealthReport> {
  /// Live app-health snapshot for the diagnostics screen. Reacts to every
  /// subsystem it reports on.
  AppHealthReportProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'appHealthReportProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$appHealthReportHash();

  @$internal
  @override
  $ProviderElement<AppHealthReport> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AppHealthReport create(Ref ref) {
    return appHealthReport(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AppHealthReport value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AppHealthReport>(value),
    );
  }
}

String _$appHealthReportHash() => r'2226c6f8b83fc127ef6e42f316c3fef23122d6b0';
