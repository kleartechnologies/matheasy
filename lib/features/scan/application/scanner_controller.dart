import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../result/application/preemptive_solve.dart';
import '../domain/detected_equation.dart';
import '../domain/scan_source.dart';
import '../domain/scan_state.dart';
import 'functions_scanner_service.dart';
import 'scan_trace.dart';
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
    final trace = ref.read(scanTraceProvider);
    try {
      // One span for the whole `recognizeEquation` round trip. It is not broken
      // down further HERE on purpose: everything inside it happens on the
      // server, which times its own three stages into the function log — this
      // side can only honestly report "the phone waited this long", which
      // includes upload and cold start and is the number the user feels.
      final equation = await (trace?.measure<DetectedEquation>(
            'recognize.roundTrip',
            () => _service.recognize(source,
                imageBytes: imageBytes, manualLatex: manualLatex),
            detail: (e) => 'confidence ${e.confidencePercent}%',
          ) ??
          _service.recognize(source,
              imageBytes: imageBytes, manualLatex: manualLatex));
      if (_disposed) return;
      state = ScanCaptured(equation);
      // The problem is known and the solve depends on nothing the user is about
      // to do, so it starts NOW rather than when they finish reading the
      // confirmation card. See [PreemptiveSolveHolder] for why this spends
      // nothing the scan hasn't already spent.
      ref.read(preemptiveSolveProvider.notifier).start(equation);
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
      // Otherwise map the failure to an honest §9 state (spec §9): a dropped
      // connection, an unreadable image, or an unexpected error each get their
      // own voice + next action rather than one generic "something went wrong".
      if (error.isQuotaExceeded) {
        state = const ScanQuotaExceeded();
      } else if (error.isOffline) {
        state = ScanError(error.message, kind: ScanErrorKind.offline);
      } else if (error.code == 'not-found') {
        state = ScanError(error.message, kind: ScanErrorKind.couldntRecognize);
      } else {
        state = ScanError(error.message);
      }
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
  void retake() {
    // A retake abandons the scan the trace was measuring; dropping it here keeps
    // the next attempt's waterfall from being timed against the previous
    // shutter press.
    ref.read(scanTraceProvider.notifier).finish();
    // The head-start solve belonged to the capture being thrown away.
    ref.read(preemptiveSolveProvider.notifier).clear();
    state = const ScanIdle();
  }

  /// Applies a user-corrected LaTeX (from the §3 detected-equation editor) to
  /// the current capture. The scan SOURCE is preserved, so re-solving the fixed
  /// problem goes through the SAME already-charged scan — never a second one.
  /// Confidence becomes 100% (a human verified it) and the kind is re-inferred.
  void applyEdit(String latex) {
    final current = state;
    if (current is! ScanCaptured) return;
    final trimmed = latex.trim();
    if (trimmed.isEmpty) return;
    final corrected = current.equation.copyWith(
      latex: trimmed,
      confidence: 1,
      kind: FunctionsScannerService.inferKind(trimmed),
    );
    state = ScanCaptured(corrected);
    // The head start was for the misread. Start again on what the user actually
    // wrote — `start` is keyed by equation, so the stale one is dropped rather
    // than able to answer for the corrected problem.
    ref.read(preemptiveSolveProvider.notifier).start(corrected);
  }

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

    // The gap between this mark and `recognize.roundTrip` ending is how long the
    // user sat on the confirmation card — dead time during which the solve
    // could already have been running.
    ref.read(scanTraceProvider)?.mark('userTappedSolve');

    state = ScanComplete(current.equation);
    unawaited(
        ref.read(analyticsServiceProvider).logEvent(AnalyticsEvent.scanCompleted()));
  }
}
