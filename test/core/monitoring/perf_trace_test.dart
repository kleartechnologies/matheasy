import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/monitoring/perf_trace.dart';

void main() {
  group('PerfTrace', () {
    test('records a span per stage, in the order it was opened', () {
      final trace = PerfTrace('scan');
      trace.begin('capture');
      trace.end('capture');
      trace.begin('recognize');
      trace.end('recognize');

      expect(trace.spans.map((s) => s.name), ['capture', 'recognize']);
    });

    test('a span starts where the previous one ended, so the waterfall is '
        'readable as a sequence', () {
      final trace = PerfTrace('scan');
      trace.begin('first');
      trace.end('first');
      trace.begin('second');
      trace.end('second');

      final [first, second] = trace.spans;
      expect(second.start, greaterThanOrEqualTo(first.end));
    });

    test('ending a stage that was never begun is ignored, not thrown', () {
      final trace = PerfTrace('scan');
      expect(() => trace.end('never-opened'), returnsNormally);
      expect(trace.spans, isEmpty);
    });

    test('measure returns the work\'s value and records a span', () async {
      final trace = PerfTrace('scan');
      final value = await trace.measure('work', () async => 42);

      expect(value, 42);
      expect(trace.spans.single.name, 'work');
    });

    test('a stage that throws is still timed — a failure has a duration too',
        () async {
      final trace = PerfTrace('scan');

      await expectLater(
        trace.measure<void>('doomed', () async => throw StateError('nope')),
        throwsStateError,
      );

      expect(trace.spans.single.name, 'doomed');
      expect(trace.spans.single.detail, contains('failed'));
    });

    test('measureSync times synchronous work', () {
      final trace = PerfTrace('scan');
      final value = trace.measureSync('sync', () => 'done');

      expect(value, 'done');
      expect(trace.spans.single.name, 'sync');
    });

    test('mark records a zero-duration point event', () {
      final trace = PerfTrace('scan');
      trace.mark('userTappedSolve');

      final span = trace.spans.single;
      expect(span.durationMs, 0);
      expect(span.name, 'userTappedSolve');
    });

    test('detail is attached to the span when supplied', () async {
      final trace = PerfTrace('scan');
      await trace.measure(
        'upload',
        () async => 'payload',
        detail: (v) => '${v.length} bytes',
      );

      expect(trace.spans.single.detail, '7 bytes');
    });

    test('the report names every stage and the total', () {
      final trace = PerfTrace('scan');
      trace.begin('capture');
      trace.end('capture', detail: '820KB');
      trace.mark('userTappedSolve');

      final report = trace.report();
      expect(report, startsWith('scan — '));
      expect(report, contains('capture'));
      expect(report, contains('820KB'));
      expect(report, contains('userTappedSolve'));
    });

    test('an empty trace still reports its total rather than crashing', () {
      expect(PerfTrace('scan').report(), startsWith('scan — '));
    });
  });
}
