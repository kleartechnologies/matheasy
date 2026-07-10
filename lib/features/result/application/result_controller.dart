import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../scan/domain/detected_equation.dart';
import '../domain/result_models.dart';
import 'solver_service.dart';

part 'result_controller.g.dart';

/// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
///
/// Async by design so a future AI solver drops straight in — the screen already
/// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
/// so re-opening the same problem reuses the cached solution.
@riverpod
class ResultController extends _$ResultController {
  @override
  Future<ResultData> build(DetectedEquation equation) async {
    final solver = ref.watch(solverServiceProvider);
    final analytics = ref.read(analyticsServiceProvider);
    final data = await solver.solve(equation);
    unawaited(analytics
        .logEvent(AnalyticsEvent.resultViewed(problemType: data.type.name)));
    return data;
  }
}

/// Remembers the last selected result tab (kept alive). Re-visiting the same
/// problem restores the tab; opening a different problem resets to Solution so
/// a new answer always starts with its solution context.
@Riverpod(keepAlive: true)
class ResultTab extends _$ResultTab {
  DetectedEquation? _lastEquation;

  @override
  int build() => 0;

  void select(int index) => state = index;

  /// Called when the result screen opens for [equation].
  void syncFor(DetectedEquation equation) {
    if (_lastEquation != equation) {
      _lastEquation = equation;
      state = 0;
    }
  }
}
