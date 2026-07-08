// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scanner_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Drives the scanner [ScanState] machine off the [ScannerService].
///
/// Auto-disposes with the scanner screen, so every launch starts fresh in
/// [ScanIdle] with live detection running.

@ProviderFor(ScannerController)
final scannerControllerProvider = ScannerControllerProvider._();

/// Drives the scanner [ScanState] machine off the [ScannerService].
///
/// Auto-disposes with the scanner screen, so every launch starts fresh in
/// [ScanIdle] with live detection running.
final class ScannerControllerProvider
    extends $NotifierProvider<ScannerController, ScanState> {
  /// Drives the scanner [ScanState] machine off the [ScannerService].
  ///
  /// Auto-disposes with the scanner screen, so every launch starts fresh in
  /// [ScanIdle] with live detection running.
  ScannerControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'scannerControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$scannerControllerHash();

  @$internal
  @override
  ScannerController create() => ScannerController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ScanState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ScanState>(value),
    );
  }
}

String _$scannerControllerHash() => r'9e562ff3749eb8d86ab1e7b9c421715348e637a6';

/// Drives the scanner [ScanState] machine off the [ScannerService].
///
/// Auto-disposes with the scanner screen, so every launch starts fresh in
/// [ScanIdle] with live detection running.

abstract class _$ScannerController extends $Notifier<ScanState> {
  ScanState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ScanState, ScanState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ScanState, ScanState>,
              ScanState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
