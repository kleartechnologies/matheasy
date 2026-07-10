import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../subscription/application/subscription_controller.dart';
import '../domain/practice_question.dart';
import '../domain/practice_session.dart';
import 'adaptive_practice_service.dart';
import 'ai_practice_generator.dart';
import 'practice_history_store.dart';
import 'practice_progress_controller.dart';
import 'practice_question_bank.dart';

/// Supplies practice questions — the seam a real content backend plugs into.
///
/// Mirrors [ScannerService]/[SolverService]/[TutorService]/[AuthService]: the
/// controller and UI depend only on this interface and the domain models, so an
/// authored-content or AI-generated implementation swaps in by overriding
/// [practiceServiceProvider] with zero UI change.
abstract interface class PracticeService {
  /// Builds a session's questions for [request].
  Future<PracticeSession> createSession(PracticeRequest request);
}

/// Timings for the mock experience, referenced by the UI/tests so the simulated
/// pace stays consistent.
class PracticeTimings {
  const PracticeTimings._();

  /// Brief "building your session" delay so the loading state is visible.
  static const Duration createSession = Duration(milliseconds: 450);
}

/// Offline, deterministic practice service backed by [PracticeQuestionBank].
class MockPracticeService implements PracticeService {
  const MockPracticeService();

  @override
  Future<PracticeSession> createSession(PracticeRequest request) async {
    await Future<void>.delayed(PracticeTimings.createSession);
    return PracticeSession(
      request: request,
      questions: _select(request),
    );
  }

  /// Picks questions for [request]: filtered to a fixed difficulty when one is
  /// set, otherwise ramped easy→hard. Deterministic (stable order) so tests and
  /// the mock experience are reproducible.
  List<PracticeQuestion> _select(PracticeRequest request) {
    final pool = [...PracticeQuestionBank.forTopic(request.topic)];
    final filtered = request.difficulty == null
        ? pool
        : pool.where((q) => q.difficulty == request.difficulty).toList();
    final source = filtered.isEmpty ? pool : filtered;

    source.sort((a, b) {
      final byDifficulty = a.difficulty.index.compareTo(b.difficulty.index);
      return byDifficulty != 0 ? byDifficulty : a.id.compareTo(b.id);
    });

    final count = request.questionCount.clamp(1, source.length);
    return source.take(count).toList();
  }
}

/// Provides the active [PracticeService] — the Stage 15 [AdaptivePracticeService]
/// (template + rule + AI generation, anti-repetition, adaptive planning). Reads
/// (not watches) progress + Pro status inside `createSession`, so the provider
/// never rebuilds in a loop when progress changes. Tests override this with a
/// fixed service; the engine also degrades to [MockPracticeService]'s bank when
/// every tier is unavailable.
final Provider<PracticeService> practiceServiceProvider =
    Provider<PracticeService>((ref) {
  return AdaptivePracticeService(
    readProgress: () => ref.read(practiceProgressControllerProvider),
    readIsPro: () => ref.read(isProProvider),
    history: ref.watch(practiceHistoryStoreProvider),
    aiGenerator: ref.watch(aiPracticeGeneratorProvider),
  );
});
