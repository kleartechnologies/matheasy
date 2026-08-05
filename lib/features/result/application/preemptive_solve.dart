import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scan/domain/detected_equation.dart';
import '../../scan/domain/scan_source.dart';
import '../domain/result_models.dart';
import 'solver_service.dart';

/// A solve that was started before the user asked for it.
@immutable
class PendingSolve {
  const PendingSolve({required this.equation, required this.future});

  /// Exactly the problem this solve was started for. A claim has to match it,
  /// because the user can correct the read on the confirmation card and a solve
  /// of the pre-correction problem is an answer to a different question.
  final DetectedEquation equation;

  final Future<ResultData> future;
}

/// Starts solving the moment the problem is recognized, instead of waiting for
/// the user to tap "Solve".
///
/// The confirmation card exists so a student can check the read against the page
/// in front of them, and checking takes a second or two. That is dead time on
/// the critical path: the problem is already known, the solve depends on nothing
/// the user is about to do, and the server would otherwise sit idle through it.
/// Running the solve during the check turns the entire time the card is on
/// screen into a head start — on a fast reader it saves a little, on a careful
/// one it can hide the whole round trip.
///
/// It changes no gate. The paywall check on "Solve" is untouched, and the solve
/// is only started for a scan the server has ALREADY charged (`countAsScan` is
/// false for camera and gallery — recognition consumed the scan). A manual
/// problem, whose solve is the charged call, is never started early.
class PreemptiveSolveHolder extends Notifier<PendingSolve?> {
  /// The pending solve that has already been handed to a result screen.
  ///
  /// Consumption is tracked HERE rather than by clearing [state], because the
  /// only caller of [claim] is `ResultController.build` — and a provider that
  /// is building may not modify another provider (Riverpod asserts on it). A
  /// private field is invisible to that rule and does the same job.
  PendingSolve? _claimed;

  @override
  PendingSolve? build() => null;

  /// Begins solving [equation] in the background, if that is free to do.
  void start(DetectedEquation equation) {
    // A typed problem's solve IS the metered call. Starting it early would spend
    // a scan the user hasn't asked to spend, and could spend it on a problem
    // they are about to correct.
    if (equation.source == ScanSource.manual) return;
    if (state?.equation == equation) return;

    final future = ref.read(solverServiceProvider).solve(equation);
    // Keep the failure from surfacing as an unhandled async error while nobody
    // is awaiting yet. The original future still carries the error to whoever
    // claims it — this only silences the zone, it does not swallow anything.
    unawaited(future.then((_) {}, onError: (_) {}));
    _claimed = null;
    state = PendingSolve(equation: equation, future: future);
  }

  /// Hands over the in-flight solve for [equation], or null if there isn't one
  /// for exactly this problem.
  ///
  /// Claiming consumes it: a second claim starts fresh. That matters for a
  /// retry after a failure — re-awaiting a future that already failed would
  /// hand back the same failure forever, and the retry button would do nothing.
  Future<ResultData>? claim(DetectedEquation equation) {
    final pending = state;
    if (pending == null || pending.equation != equation) return null;
    if (identical(pending, _claimed)) return null;
    _claimed = pending;
    return pending.future;
  }

  /// Drops any in-flight solve. Its result is simply never read — the request is
  /// already out and cannot be recalled, which is the honest cost of starting
  /// early and the reason this is limited to already-charged scans.
  void clear() {
    _claimed = null;
    state = null;
  }
}

final NotifierProvider<PreemptiveSolveHolder, PendingSolve?>
    preemptiveSolveProvider =
    NotifierProvider<PreemptiveSolveHolder, PendingSolve?>(
        PreemptiveSolveHolder.new);
