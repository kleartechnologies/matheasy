import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/detected_equation.dart';
import '../domain/scan_source.dart';
import '../domain/scan_state.dart';
import 'scanner_service.dart';

part 'scanner_controller.g.dart';

/// Drives the scanner [ScanState] machine off the [ScannerService].
///
/// Auto-disposes with the scanner screen, so every launch starts fresh in
/// [ScanIdle] with live detection running.
@riverpod
class ScannerController extends _$ScannerController {
  late final ScannerService _service;
  StreamSubscription<DetectedEquation?>? _sub;
  Timer? _processTimer;
  bool _disposed = false;

  @override
  ScanState build() {
    _service = ref.read(scannerServiceProvider);
    ref.onDispose(() {
      _disposed = true;
      _sub?.cancel();
      _processTimer?.cancel();
    });
    _listen();
    return const ScanIdle();
  }

  void _listen() {
    _sub?.cancel();
    _sub = _service.liveDetections().listen((equation) {
      if (equation != null && state is ScanIdle) {
        state = ScanDetecting(equation);
      }
    });
  }

  /// Shutter / gallery / manual entry. If a live candidate already exists and
  /// this is a camera capture, it's used directly for an instant response.
  Future<void> capture(ScanSource source) async {
    // Cancel live detection fire-and-forget: awaiting it would block until the
    // mock stream's delay resolves. Stale emissions are ignored by _listen's
    // `state is ScanIdle` guard.
    final subscription = _sub;
    _sub = null;
    if (subscription != null) unawaited(subscription.cancel());

    final current = state;
    final equation = (current is ScanDetecting && source == ScanSource.camera)
        ? current.candidate
        : await _service.recognize(source);
    if (_disposed) return;
    state = ScanCaptured(equation);
  }

  /// Discards the capture and resumes live detection.
  void retake() {
    _processTimer?.cancel();
    state = const ScanIdle();
    _listen();
  }

  /// Confirms the capture and runs the (simulated) analysis, ending in
  /// [ScanComplete] which the screen hands off to the result route.
  void confirm() {
    final current = state;
    if (current is! ScanCaptured) return;
    state = ScanProcessing(current.equation);
    _processTimer?.cancel();
    _processTimer = Timer(ScannerTimings.processing, () {
      if (state is ScanProcessing) {
        state = ScanComplete(current.equation);
      }
    });
  }
}
