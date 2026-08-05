import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/monitoring/perf_trace.dart';

/// The [PerfTrace] for the scan currently in flight, or `null` between scans.
///
/// A shared holder rather than a parameter threaded through every call because
/// the scan crosses four owners that never see each other — the scanner screen
/// (camera, capture), the crop screen (a pushed route), the scanner controller
/// (recognition) and the result controller (solve, on a different screen
/// entirely) — and the whole point of the measurement is that it spans all of
/// them. Threading an argument through would have meant changing the
/// `ScannerService` and `SolverService` interfaces to carry a profiler, which is
/// exactly the kind of contamination that gets ripped out later and takes the
/// measurement with it.
///
/// Every read is null-tolerant: a scan that starts without a trace (a test, a
/// deep link straight into a result) simply is not measured.
final NotifierProvider<ScanTraceHolder, PerfTrace?> scanTraceProvider =
    NotifierProvider<ScanTraceHolder, PerfTrace?>(ScanTraceHolder.new);

class ScanTraceHolder extends Notifier<PerfTrace?> {
  @override
  PerfTrace? build() => null;

  /// Starts a fresh trace for a new scan, discarding any previous one.
  PerfTrace start() {
    final trace = PerfTrace('scan');
    state = trace;
    return trace;
  }

  /// Logs the finished waterfall and clears the trace.
  ///
  /// Only safe to call from an event handler. A provider that is BUILDING must
  /// not mutate another provider (Riverpod asserts on it), so the result
  /// controller — which finishes the trace from inside its own `build` — calls
  /// [PerfTrace.log] directly and leaves the holder for the next [start] to
  /// replace.
  void finish() {
    state?.log();
    state = null;
  }
}
