import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../../settings/application/language_provider.dart';
import '../domain/tutor_models.dart';
import 'functions_tutor_service.dart';
import 'tutor_reply_engine.dart';

/// The AI tutor provider — turns a student's message into an educational
/// [TutorResponse] (text + optional inline card + follow-up suggestions).
///
/// This is the single seam a real model plugs into: swap [MockTutorService]
/// for an OpenAI/Claude-backed implementation by overriding
/// [tutorServiceProvider]. The chat controller and every widget depend only on
/// this interface and the domain models, so no UI changes when the AI lands.
abstract interface class TutorService {
  /// The opening turn when a chat starts — problem-aware when [context] carries
  /// a recognized problem, and pitched to [mode] once the student has chosen how
  /// they want to learn.
  TutorResponse greeting(TutorLaunchContext? context, {TutorMode? mode});

  /// Numi's reply to [userText], given the running [history], the teaching
  /// [mode] the student picked, what Numi has learned about them ([memory]) and
  /// the optional problem [context]. Async so a network-backed model drops
  /// straight in — the UI already renders a typing state while this resolves.
  ///
  /// [studentWork] carries the lines transcribed from a photo of the student's
  /// own working (spec Part 12). The server checks them against the verified
  /// solution *deterministically* and hands the model the verdict as a fact —
  /// the model narrates where it went wrong, it never decides.
  ///
  /// [onDelta] receives the reply text as it is written (spec Part 18): each
  /// call carries the *next* piece, so the caller appends rather than replaces.
  /// It is a request, not a promise — an implementation with nothing to stream
  /// simply never calls it, and the returned [TutorResponse] is authoritative
  /// either way.
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
    TutorMode mode,
    TutorMemory memory,
    List<String> studentWork,
    void Function(String delta)? onDelta,
  });
}

/// Timings for the mock experience — also referenced by the UI/tests so the
/// simulated "thinking" pace stays consistent.
class TutorTimings {
  const TutorTimings._();

  /// Simulated time Numi spends "thinking" before a reply appears. Long
  /// enough to show the typing indicator, short enough to stay snappy.
  static const Duration thinking = Duration(milliseconds: 900);
}

/// Offline, deterministic tutor backed by the [TutorReplyEngine]. Feels
/// conversational (a brief thinking delay) while staying fully reproducible.
class MockTutorService implements TutorService {
  const MockTutorService({this.engine = const TutorReplyEngine()});

  final TutorReplyEngine engine;

  @override
  TutorResponse greeting(TutorLaunchContext? context, {TutorMode? mode}) =>
      engine.greeting(context, mode: mode);

  @override
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
    TutorMode mode = TutorMode.fallback,
    TutorMemory memory = const TutorMemory(),
    // Ignored offline, and that is the correct behaviour: checking a line of
    // working needs the verified solution the engine doesn't have, and guessing
    // at it would be the model inventing arithmetic.
    List<String> studentWork = const [],
    // Nothing to stream: the engine composes the whole reply in one synchronous
    // step, so faking a trickle would be theatre rather than lower latency.
    void Function(String delta)? onDelta,
  }) async {
    await Future<void>.delayed(TutorTimings.thinking);
    return engine.reply(
      userText,
      history: history,
      context: context,
      mode: mode,
    );
  }
}

/// Provides the active [TutorService]: the real Cloud-Function tutor for
/// signed-in users with Firebase configured, else the offline mock.
final Provider<TutorService> tutorServiceProvider =
    Provider<TutorService>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) return const MockTutorService();
  final functions = ref.watch(firebaseFunctionsProvider);
  final ctx = ref.watch(aiRequestContextProvider);
  return FunctionsTutorService(
    (name, data) => callFunction(functions, name, {...data, ...ctx}),
    // The same call over SSE, so the reply can be rendered as it is written.
    stream: (name, data, onChunk) => streamFunction(
      functions,
      name,
      {...data, ...ctx},
      onChunk: onChunk,
    ),
  );
});
