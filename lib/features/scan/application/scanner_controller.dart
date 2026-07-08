import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
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
  Future<void> capture(
    ScanSource source, {
    Uint8List? imageBytes,
    String? manualLatex,
  }) async {
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.scanStarted(source: source.name)));
    // Cancel live detection fire-and-forget: awaiting it would block until the
    // mock stream's delay resolves. Stale emissions are ignored by _listen's
    // `state is ScanIdle` guard.
    final subscription = _sub;
    _sub = null;
    if (subscription != null) unawaited(subscription.cancel());

    final current = state;
    // Use a live mock candidate only when no real photo was supplied.
    if (current is ScanDetecting &&
        source == ScanSource.camera &&
        imageBytes == null &&
        manualLatex == null) {
      state = ScanCaptured(current.candidate);
      return;
    }

    try {
      final equation = await _service.recognize(
        source,
        imageBytes: imageBytes,
        manualLatex: manualLatex,
      );
      if (_disposed) return;
      state = ScanCaptured(equation);
    } on BackendException catch (error) {
      if (_disposed) return;
      LoggingService.warning('Recognition failed: ${error.code}');
      state = ScanError(error.message);
    } catch (error, stack) {
      if (_disposed) return;
      LoggingService.error('Recognition error', error: error, stackTrace: stack);
      state = const ScanError('Something went wrong. Please try again.');
    }
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

    // Client-side abuse guard (server enforcement is authoritative). Generous
    // limits mean a human never hits this; a stuck/automated loop is throttled.
    final limit = ref.read(rateLimitServiceProvider).check(RateLimitedAction.scan);
    if (limit.isLimited) {
      LoggingService.warning('Scan rate-limited: ${limit.reason}');
      return;
    }

    state = ScanProcessing(current.equation);
    _processTimer?.cancel();
    _processTimer = Timer(ScannerTimings.processing, () {
      if (state is ScanProcessing) {
        state = ScanComplete(current.equation);
        unawaited(ref
            .read(analyticsServiceProvider)
            .logEvent(AnalyticsEvent.scanCompleted()));
      }
    });
  }
}
