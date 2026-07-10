import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../domain/scan_source.dart';
import '../domain/scan_state.dart';
import 'scanner_service.dart';

part 'scanner_controller.g.dart';

/// Drives the scanner [ScanState] machine off the [ScannerService].
///
/// Auto-disposes with the scanner screen, so every launch starts fresh in
/// [ScanIdle] with the live camera preview.
@riverpod
class ScannerController extends _$ScannerController {
  late final ScannerService _service;
  bool _disposed = false;

  @override
  ScanState build() {
    _service = ref.read(scannerServiceProvider);
    ref.onDispose(() => _disposed = true);
    return const ScanIdle();
  }

  /// Recognizes a captured/cropped photo (camera / gallery) or a typed problem
  /// (manual). Moves through [ScanRecognizing] to [ScanCaptured] on success, or
  /// [ScanError] on failure. Ignored if a recognition is already in flight.
  Future<void> recognize(
    ScanSource source, {
    Uint8List? imageBytes,
    String? manualLatex,
  }) async {
    if (state is ScanRecognizing) return;

    final analytics = ref.read(analyticsServiceProvider);
    unawaited(analytics.logEvent(AnalyticsEvent.scanStarted(source: source.name)));

    state = const ScanRecognizing();
    try {
      final equation = await _service.recognize(
        source,
        imageBytes: imageBytes,
        manualLatex: manualLatex,
      );
      if (_disposed) return;
      state = ScanCaptured(equation);
      unawaited(analytics.logEvent(AnalyticsEvent.recognitionSucceeded(
        source: source.name,
        confidence: equation.confidencePercent,
      )));
    } on BackendException catch (error) {
      if (_disposed) return;
      LoggingService.warning('Recognition failed: ${error.code}');
      unawaited(analytics.logEvent(AnalyticsEvent.recognitionFailed(
        source: source.name,
        reason: error.code,
      )));
      // The server can reject on quota even if the optimistic client counter is
      // behind — hand the screen a paywall signal rather than a raw error.
      state = error.isQuotaExceeded
          ? const ScanQuotaExceeded()
          : ScanError(error.message);
    } catch (error, stack) {
      if (_disposed) return;
      LoggingService.error('Recognition error', error: error, stackTrace: stack);
      unawaited(analytics.logEvent(AnalyticsEvent.recognitionFailed(
        source: source.name,
        reason: 'unknown',
      )));
      state = const ScanError('Something went wrong. Please try again.');
    }
  }

  /// Discards the current capture / error and returns to the live preview.
  void retake() => state = const ScanIdle();

  /// Confirms the recognized problem and hands off to the result screen (which
  /// runs the real solve). [ScanComplete] is the signal the screen listens for.
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

    state = ScanComplete(current.equation);
    unawaited(
        ref.read(analyticsServiceProvider).logEvent(AnalyticsEvent.scanCompleted()));
  }
}
