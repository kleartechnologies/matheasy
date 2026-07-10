import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
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
///
/// ### Streaming later
/// Real streaming is additive: add `Stream<String> replyStream(...)` here and
/// have the controller consume it. The current [reply] contract stays valid, so
/// nothing that exists today needs rewriting.
abstract interface class TutorService {
  /// The opening turn when a chat starts — scan-aware when [context] carries a
  /// recognized problem.
  TutorResponse greeting(TutorLaunchContext? context);

  /// Matheasy's reply to [userText], given the running [history] and optional
  /// scan [context]. Async so a network-backed model drops straight in — the UI
  /// already renders a typing state while this resolves.
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
  });
}

/// Timings for the mock experience — also referenced by the UI/tests so the
/// simulated "thinking" pace stays consistent.
class TutorTimings {
  const TutorTimings._();

  /// Simulated time Matheasy spends "thinking" before a reply appears. Long
  /// enough to show the typing indicator, short enough to stay snappy.
  static const Duration thinking = Duration(milliseconds: 900);
}

/// Offline, deterministic tutor backed by the [TutorReplyEngine]. Feels
/// conversational (a brief thinking delay) while staying fully reproducible.
class MockTutorService implements TutorService {
  const MockTutorService({this.engine = const TutorReplyEngine()});

  final TutorReplyEngine engine;

  @override
  TutorResponse greeting(TutorLaunchContext? context) =>
      engine.greeting(context);

  @override
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
  }) async {
    await Future<void>.delayed(TutorTimings.thinking);
    return engine.reply(userText, history: history, context: context);
  }
}

/// Provides the active [TutorService]: the real Cloud-Function tutor for
/// signed-in users with Firebase configured, else the offline mock.
final Provider<TutorService> tutorServiceProvider =
    Provider<TutorService>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) return const MockTutorService();
  final functions = ref.watch(firebaseFunctionsProvider);
  return FunctionsTutorService(
    (name, data) => callFunction(functions, name, data),
  );
});
