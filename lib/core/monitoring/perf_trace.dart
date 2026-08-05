import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import 'logging_service.dart';

/// A stage in a traced pipeline, with the wall-clock window it occupied.
///
/// [start] and [end] are milliseconds from the trace's own origin, not epoch —
/// so a span is directly readable as "this happened 1.2s in and took 400ms",
/// and two spans that overlap are visibly concurrent.
@immutable
class PerfSpan {
  const PerfSpan({
    required this.name,
    required this.start,
    required this.end,
    this.detail,
  });

  final String name;
  final int start;
  final int end;

  /// Optional context that explains the number — a byte count, a code path
  /// taken, a cache hit. Never PII: this is logged.
  final String? detail;

  int get durationMs => end - start;

  /// True while the span is still open (see [PerfTrace.begin]).
  bool get isOpen => end < start;
}

/// Records how long each stage of a pipeline actually took.
///
/// Built for the scanner audit: the scan→solve path crosses the camera plugin,
/// two isolates, a human crop step, a Cloud Function that itself makes three
/// sequential OpenAI calls, and finally a rebuild — and until this existed not
/// one of those boundaries reported a duration, so "the scanner feels slow" had
/// no evidence behind it and no way to tell an optimisation from a placebo.
///
/// Deliberately dependency-free and allocation-cheap (one [Stopwatch] plus a
/// span per stage), so it can stay wired into the real path in release rather
/// than being a debug-only harness that rots. The summary is emitted at
/// [LogLevel.debug], which [LoggingService] drops in release, so the cost in a
/// shipped build is the stopwatch and nothing else.
///
/// Spans are also mirrored to `dart:developer`'s Timeline, so the same run shows
/// up as flow events in DevTools next to the frame chart — which is how you tell
/// "the isolate took 900ms" from "the isolate took 900ms AND janked the UI".
class PerfTrace {
  PerfTrace(this.label) : _watch = Stopwatch()..start();

  /// Names the pipeline being traced, e.g. `scan`. Used as the log prefix.
  final String label;

  final Stopwatch _watch;
  final List<PerfSpan> _spans = <PerfSpan>[];
  final Map<String, int> _open = <String, int>{};

  /// Every completed span, in the order it was opened.
  List<PerfSpan> get spans => List.unmodifiable(_spans);

  /// Total elapsed time since the trace was created.
  int get totalMs => _watch.elapsedMilliseconds;

  /// Opens a span named [name]. Pair with [end].
  ///
  /// Re-opening an already-open name is tolerated (the later start wins) rather
  /// than throwing: a trace must never be able to break the flow it measures.
  void begin(String name) {
    _open[name] = _watch.elapsedMilliseconds;
    developer.Timeline.startSync('$label.$name');
  }

  /// Closes the span named [name]. A no-op if it was never opened.
  void end(String name, {String? detail}) {
    final start = _open.remove(name);
    if (start == null) return;
    developer.Timeline.finishSync();
    _spans.add(PerfSpan(
      name: name,
      start: start,
      end: _watch.elapsedMilliseconds,
      detail: detail,
    ));
  }

  /// Records an instantaneous marker — a point event with no duration, for
  /// things like "first frame rendered" or "user tapped Solve".
  void mark(String name, {String? detail}) {
    final at = _watch.elapsedMilliseconds;
    _spans.add(PerfSpan(name: name, start: at, end: at, detail: detail));
  }

  /// Times [work] as a span named [name] and returns its result.
  ///
  /// The span is closed even when [work] throws, so a failed stage still reports
  /// how long it burned before failing — which is exactly the case you most want
  /// a number for.
  Future<T> measure<T>(
    String name,
    Future<T> Function() work, {
    String Function(T value)? detail,
  }) async {
    begin(name);
    try {
      final result = await work();
      end(name, detail: detail?.call(result));
      return result;
    } catch (error) {
      end(name, detail: 'failed: ${error.runtimeType}');
      rethrow;
    }
  }

  /// The same as [measure] for synchronous work.
  T measureSync<T>(String name, T Function() work, {String Function(T)? detail}) {
    begin(name);
    try {
      final result = work();
      end(name, detail: detail?.call(result));
      return result;
    } catch (error) {
      end(name, detail: 'failed: ${error.runtimeType}');
      rethrow;
    }
  }

  /// A human-readable timeline: one line per stage, with the offset it began at,
  /// how long it ran, and its share of the total.
  ///
  /// Rendered as a waterfall because the shape is the finding — a column of
  /// bars that never overlap is a pipeline with nothing running in parallel,
  /// and that reads at a glance in a way a list of durations does not.
  String report() {
    final total = totalMs;
    final buffer = StringBuffer('$label — ${total}ms total\n');
    if (_spans.isEmpty) return buffer.toString();

    final width = _spans.map((s) => s.name.length).reduce((a, b) => a > b ? a : b);
    for (final span in _spans) {
      final share = total == 0 ? 0.0 : span.durationMs / total;
      final bar = _bar(span, total);
      buffer.writeln(
        '  ${span.name.padRight(width)}  '
        '${'${span.durationMs}ms'.padLeft(7)}  '
        '${'${(share * 100).toStringAsFixed(1)}%'.padLeft(6)}  '
        '@${span.start}ms  $bar'
        '${span.detail == null ? '' : '  (${span.detail})'}',
      );
    }
    return buffer.toString();
  }

  /// A 40-column ASCII bar positioned at the span's offset, so the waterfall
  /// shows WHEN each stage ran, not just how long it took.
  static String _bar(PerfSpan span, int total) {
    if (total <= 0) return '';
    const columns = 40;
    final from = (span.start / total * columns).floor().clamp(0, columns - 1);
    final to = (span.end / total * columns).ceil().clamp(from + 1, columns);
    return '${'.' * from}${'#' * (to - from)}${'.' * (columns - to)}';
  }

  bool _logged = false;

  /// Emits [report] through [LoggingService] at debug level, at most once.
  ///
  /// Idempotent because a scan can reach its end through more than one path (a
  /// solve, a cache hit, a retake, an error) and each one closes the trace; a
  /// trace that printed twice would read as two scans.
  void log() {
    if (_logged) return;
    _logged = true;
    LoggingService.debug(report(), name: 'matheasy.perf');
  }
}
