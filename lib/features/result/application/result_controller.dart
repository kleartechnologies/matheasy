import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/functions_client.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../history/application/history_controller.dart';
import '../../history/application/history_repository.dart';
import '../../history/domain/history_entry.dart';
import '../../scan/application/scan_trace.dart';
import '../../scan/domain/detected_equation.dart';
import '../domain/result_models.dart';
import 'functions_teaching_service.dart';
import 'preemptive_solve.dart';
import 'solver_service.dart';

part 'result_controller.g.dart';

/// Raised when `solve()` fails outright — a network drop or a backend error, as
/// opposed to a successful-but-`verified:false` result (spec §1.1). Carries
/// [offline] so the result screen shows the right honest §9 state.
///
/// Modeled as an [Error], not an [Exception], on purpose: an async provider that
/// throws a plain `Exception` does not reliably surface through Riverpod's async
/// error channel (it can hang the screen on the loading state), whereas an
/// `Error` does. Wrapping the failure here guarantees the screen never spins
/// forever when the solve fails offline.
class ResultSolveFailure extends Error {
  ResultSolveFailure({required this.offline});

  /// The solve failed because the request never reached the server.
  final bool offline;
}

/// Solves a [DetectedEquation] into [ResultData] via the [SolverService].
///
/// Async by design so a future AI solver drops straight in — the screen already
/// renders `loading` (Matheasy solving) and `error` states. Keyed by the equation,
/// so re-opening the same problem reuses the cached solution.
@riverpod
class ResultController extends _$ResultController {
  @override
  Future<ResultData> build(DetectedEquation equation) async {
    final analytics = ref.read(analyticsServiceProvider);

    // The in-flight scan's trace, closed on every exit below so the waterfall
    // always covers shutter → answer. Finished with [PerfTrace.log] rather than
    // through the holder because this runs inside `build`, and a provider may
    // not mutate another provider while building; the next scan's `start()`
    // replaces it.
    final trace = ref.read(scanTraceProvider);

    // Read-through cache (spec §8). A previously solved problem re-opens from the
    // local store — no `solve()` call, no scan charge (the meter lives in the
    // scanner flow, which this bypasses), and it works offline.
    final cached = _lookupCache(equation);
    if (cached != null) {
      trace?.mark('solve.cacheHit');
      trace?.log();
      unawaited(analytics.logEvent(
          AnalyticsEvent.resultViewed(problemType: cached.result.type.name)));
      // Progressive teaching for a RE-OPENED problem too (the common case): the
      // cached entry may predate teaching, or its first fetch never completed.
      // The teaching==null guard fetches once; _recordCache(merged) then upserts
      // the enriched entry so subsequent opens skip it.
      if (cached.result.teaching == null &&
          (cached.result.verified || cached.result.routeToTutor)) {
        unawaited(_attachTeaching(cached.result));
      }
      return cached.result;
    }

    final solver = ref.watch(solverServiceProvider);
    // A solve started while the user was checking the confirmation card. When
    // there is one it is already seconds old by the time this screen builds, so
    // awaiting it is what turns that reading time into a head start. Claiming
    // consumes it, so a retry after a failure starts a genuinely new solve
    // instead of re-awaiting the same broken future.
    final headStart =
        ref.read(preemptiveSolveProvider.notifier).claim(equation);
    Future<ResultData> run() => headStart ?? solver.solve(equation);

    final ResultData data;
    try {
      // The last leg of the scan waterfall: `solveEquation`'s round trip, which
      // on an LLM-tier problem is a second reasoning-model call plus a possible
      // verification-gate retry. Closing the trace right after logs the full
      // shutter → answer path as one waterfall. With a head start this span
      // measures only what was LEFT of that round trip, which is the point.
      data = await (trace?.measure<ResultData>(
            'solve.roundTrip',
            run,
            detail: (d) => '${d.verified ? 'verified' : 'unverified'}'
                '${headStart != null ? ', pre-emptive' : ''}',
          ) ??
          run());
    } on BackendException catch (e) {
      trace?.log();
      throw ResultSolveFailure(offline: e.isOffline);
    } catch (_) {
      trace?.log();
      throw ResultSolveFailure(offline: false);
    }
    // The answer is on screen from here — teaching enrichment that follows is
    // explicitly off the critical path and must not be counted in it.
    ref.read(scanTraceProvider.notifier).finish();
    // Cache only real answers: a couldn't-verify result is never stored, so a
    // re-scan gets a fresh attempt and history stays a log of solved problems.
    if (data.verified) await _recordCache(data);
    unawaited(analytics
        .logEvent(AnalyticsEvent.resultViewed(problemType: data.type.name)));
    // Progressive teaching (spec §5): the answer is already computed — fetch the
    // teaching layer on a SEPARATE call so it never delays the solution, then pop
    // it in. Best-effort; a failure just leaves the plain solution. Fetched for a
    // verified solve (full/lite) AND a routeToTutor problem (honest concept
    // teaching); a couldn't-verify (likely a misread) is left untaught.
    if (data.teaching == null && (data.verified || data.routeToTutor)) {
      unawaited(_attachTeaching(data));
    }
    return data;
  }

  /// Fetches the teaching layer for [base] and, if present, re-emits the enriched
  /// result + refreshes the cache. Best-effort: swallows failures (including a
  /// set-after-dispose if the user navigated away mid-fetch).
  Future<void> _attachTeaching(ResultData base) async {
    try {
      final merged = await ref.read(teachingServiceProvider).enrich(base);
      // Bail if there's no layer, or if the provider was disposed / rebuilt while
      // the fetch was in flight (don't stomp a newer state — review #3).
      if (merged == null || !ref.mounted) return;
      state = AsyncData(merged);
      if (merged.verified) await _recordCache(merged);
    } catch (_) {
      // Teaching is an enhancement — never surface its failure over the answer.
    }
  }

  /// Looks up the local cache, degrading to a miss if the store is unavailable
  /// — history is an enhancement and must never block solving.
  HistoryEntry? _lookupCache(DetectedEquation equation) {
    try {
      return ref.read(historyRepositoryProvider).lookup(equation.latex);
    } catch (_) {
      return null;
    }
  }

  /// Records a solved problem (routed through the controller so History + the
  /// sync layer see the entry). A persistence failure must not fail the solve.
  Future<void> _recordCache(ResultData data) async {
    try {
      await ref.read(historyControllerProvider.notifier).record(data);
    } catch (_) {
      // History is a best-effort cache; swallow store failures.
    }
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
