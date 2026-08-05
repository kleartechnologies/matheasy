import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/preemptive_solve.dart';
import 'package:matheasy/features/result/application/solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

/// Counts calls and hands back a future the test controls, so "did the solve
/// start early?" and "did the head start get reused?" are both observable.
class _RecordingSolver implements SolverService {
  final List<DetectedEquation> calls = [];
  final List<Completer<ResultData>> completers = [];

  @override
  Future<ResultData> solve(DetectedEquation equation) {
    calls.add(equation);
    final completer = Completer<ResultData>();
    completers.add(completer);
    return completer.future;
  }
}

DetectedEquation _equation({
  String latex = '2x + 5 = 13',
  ScanSource source = ScanSource.camera,
}) =>
    DetectedEquation(
      latex: latex,
      confidence: 1,
      source: source,
      kind: EquationKind.linear,
    );

ResultData _result(DetectedEquation equation) => ResultData(
      equation: equation,
      type: ResultType.linear,
      difficulty: Difficulty.easy,
      answerLatex: 'x = 4',
      verifyText: 'Check: 2(4) + 5 = 13',
      tutorIntro: '',
      steps: const [],
      methods: const [],
      explanations: const [],
      practice: const [],
    );

void main() {
  late _RecordingSolver solver;
  late ProviderContainer container;

  setUp(() {
    solver = _RecordingSolver();
    container = ProviderContainer(
      overrides: [solverServiceProvider.overrideWithValue(solver)],
    );
  });

  tearDown(() => container.dispose());

  PreemptiveSolveHolder holder() =>
      container.read(preemptiveSolveProvider.notifier);

  test('a scanned problem starts solving before anyone asks', () {
    final equation = _equation();
    holder().start(equation);

    expect(solver.calls, [equation]);
    expect(container.read(preemptiveSolveProvider)?.equation, equation);
  });

  test('a typed problem is never solved early', () {
    // The monetization guard: `countAsScan` is true only for a manual problem,
    // so starting it early would spend a scan the user has not asked to spend
    // — and could spend it on a problem they are about to correct.
    holder().start(_equation(source: ScanSource.manual));

    expect(solver.calls, isEmpty);
    expect(container.read(preemptiveSolveProvider), isNull);
  });

  test('starting the same problem twice does not solve it twice', () {
    holder()
      ..start(_equation())
      ..start(_equation());

    expect(solver.calls, hasLength(1));
  });

  test('claiming hands back the in-flight solve rather than starting a new one',
      () async {
    final equation = _equation();
    holder().start(equation);

    final claimed = holder().claim(equation);
    expect(claimed, isNotNull);
    expect(solver.calls, hasLength(1));

    solver.completers.single.complete(_result(equation));
    expect((await claimed!).answerLatex, 'x = 4');
  });

  test('a corrected problem cannot claim the misread problem\'s solve', () {
    // The read is editable on the confirmation card. A solve of the
    // pre-correction problem is an answer to a different question, so it must
    // not be able to answer for the corrected one.
    holder().start(_equation());

    expect(holder().claim(_equation(latex: '2x + 5 = 18')), isNull);
  });

  test('claiming consumes, so a retry gets a genuinely new solve', () {
    final equation = _equation();
    holder()
      ..start(equation)
      ..claim(equation);

    // Re-awaiting a future that already failed would hand back the same
    // failure forever and the retry button would do nothing.
    expect(holder().claim(equation), isNull);
  });

  test('a retake drops the head start', () {
    final equation = _equation();
    holder()
      ..start(equation)
      ..clear();

    expect(container.read(preemptiveSolveProvider), isNull);
    expect(holder().claim(equation), isNull);
  });

  test('a failing head start does not escape as an unhandled async error',
      () async {
    final equation = _equation();
    holder().start(equation);
    solver.completers.single.completeError(StateError('backend down'));

    // Nothing is awaiting yet; the zone must stay quiet.
    await Future<void>.delayed(Duration.zero);

    // ...and the failure still reaches whoever claims it.
    await expectLater(holder().claim(equation), throwsStateError);
  });
}
