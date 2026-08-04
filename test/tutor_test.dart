// Stage 6 tests — the AI Tutor (Matheasy).
//
// Covers: the deterministic reply engine (intent → response + cards), the chat
// controller's send/typing/reset/load loop, the mock home content, and the key
// widgets (Tutor home, chat send flow, interactive quiz card). pump() (not
// pumpAndSettle) is used because Matheasy's typing animations loop forever.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/core/persistence/preferences_store.dart';
import 'package:matheasy/core/theme/app_semantic_colors.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/core/theme/math_semantics.dart';
import 'package:matheasy/core/widgets/chat/highlighted_math.dart';
import 'package:matheasy/features/result/application/solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/subscription/application/usage_tracker.dart';
import 'package:matheasy/features/subscription/domain/usage_counts.dart';
import 'package:matheasy/features/tutor/application/tutor_controller.dart';
import 'package:matheasy/features/tutor/application/tutor_image_service.dart';
import 'package:matheasy/features/tutor/application/tutor_reply_engine.dart';
import 'package:matheasy/features/tutor/application/tutor_service.dart';
import 'package:matheasy/features/tutor/domain/tutor_models.dart';
import 'package:matheasy/features/tutor/presentation/tutor_chat_screen.dart';
import 'package:matheasy/features/tutor/presentation/tutor_screen.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_message_view.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_quiz_card.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_sketch_view.dart';
import 'package:matheasy/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A zero-delay [TutorService] so controller/widget tests don't wait on the
/// mock "thinking" pause. Uses the real engine, so replies stay realistic.
class _InstantTutorService implements TutorService {
  _InstantTutorService();

  static const TutorReplyEngine _engine = TutorReplyEngine();

  /// The lines the last [reply] was told the student had written (spec Part 12).
  List<String> lastStudentWork = const [];

  @override
  TutorResponse greeting(TutorLaunchContext? context, {TutorMode? mode}) =>
      _engine.greeting(context, mode: mode);

  @override
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
    TutorMode mode = TutorMode.fallback,
    TutorMemory memory = const TutorMemory(),
    // Recorded, not acted on: checking a student's working against the verified
    // solution happens server-side, so the offline engine has nothing to say.
    List<String> studentWork = const [],
    // Nothing to stream — this fake answers in one step, like the real offline
    // engine. The streaming path has its own double below.
    void Function(String delta)? onDelta,
  }) async {
    lastStudentWork = studentWork;
    return _engine.reply(userText, history: history, context: context,
        mode: mode);
  }
}

/// A [TutorService] that streams its reply in pieces, the way the real
/// `tutorReply` does over SSE (spec Part 18). The final [TutorResponse] carries
/// [finalText] — deliberately allowed to differ from the streamed pieces, so a
/// test can prove the authoritative value is what lands.
class _StreamingTutorService implements TutorService {
  _StreamingTutorService({
    this.deltas = const ['One ', 'two ', 'three.'],
    String? finalText,
    this.suggestions = const [SuggestionAction.tellMeWhy],
    this.error,
  }) : finalText = finalText ?? deltas.join();

  final List<String> deltas;
  final String finalText;
  final List<SuggestionAction> suggestions;

  /// Thrown after the deltas are delivered, to model a stream that drops
  /// part-way through the answer.
  final Object? error;

  /// The session as the controller had rendered it after each delta, so a test
  /// can watch the bubble grow rather than only see where it ended up.
  final List<TutorSession> snapshots = <TutorSession>[];

  /// The lines the last [reply] was told the student had written (spec Part 12).
  List<String> lastStudentWork = const [];

  /// Set by the test to read state back mid-stream.
  TutorSession Function()? read;

  @override
  TutorResponse greeting(TutorLaunchContext? context, {TutorMode? mode}) =>
      const TutorReplyEngine().greeting(context, mode: mode);

  @override
  Future<TutorResponse> reply(
    String userText, {
    required List<TutorMessage> history,
    TutorLaunchContext? context,
    TutorMode mode = TutorMode.fallback,
    TutorMemory memory = const TutorMemory(),
    List<String> studentWork = const [],
    void Function(String delta)? onDelta,
  }) async {
    lastStudentWork = studentWork;
    for (final delta in deltas) {
      onDelta?.call(delta);
      final peek = read?.call();
      if (peek != null) snapshots.add(peek);
    }
    final failure = error;
    if (failure != null) throw failure;
    return TutorResponse(text: finalText, suggestions: suggestions);
  }
}

/// A [TutorImageService] with a scripted outcome, so every branch of the photo
/// flow — read, unreadable, not-math, backend failure, spent quota — is
/// reachable without a Firebase stub.
class _ScriptedImageService implements TutorImageService {
  _ScriptedImageService({
    this.result = TutorImageRead.unreadable,
    this.error,
  });

  final TutorImageRead result;
  final Object? error;
  int calls = 0;

  @override
  Future<TutorImageRead> read(
    Uint8List imageBytes, {
    String caption = '',
  }) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return result;
  }
}

/// Records what the photo flow handed to the app's own solver — the golden-rule
/// check: a problem photographed in chat must be solved deterministically, not
/// read off the model's answer.
class _RecordingSolver implements SolverService {
  final List<DetectedEquation> seen = <DetectedEquation>[];

  @override
  Future<ResultData> solve(DetectedEquation equation) {
    seen.add(equation);
    return const MockSolverService().solve(equation);
  }
}

/// Tagged stand-ins for the localized photo copy, so a test can tell which line
/// the controller chose without depending on the English wording.
const TutorImageCopy _imageCopy = TutorImageCopy(
  askProblem: 'ASK_PROBLEM',
  askWork: 'ASK_WORK',
  sawProblem: 'SAW_PROBLEM',
  sawWork: 'SAW_WORK',
  notMath: 'NOT_MATH',
  unreadable: 'UNREADABLE',
  failed: 'FAILED',
);

final Uint8List _photo = Uint8List.fromList(const [1, 2, 3, 4]);

/// In-memory usage tracker so tutor controller tests need no SharedPreferences —
/// sending a message now records against the free-tier AI tutor quota via the
/// controller.
class _MemoryUsageTracker implements UsageTracker {
  UsageCounts _counts = UsageCounts.empty;

  @override
  UsageCounts load() => _counts;

  @override
  Future<void> save(UsageCounts counts) async => _counts = counts;
}

ProviderContainer _instantContainer({
  TutorService? tutor,
  TutorImageService? images,
  SolverService? solver,
}) {
  final container = ProviderContainer(
    overrides: [
      tutorServiceProvider.overrideWithValue(tutor ?? _InstantTutorService()),
      usageTrackerProvider.overrideWithValue(_MemoryUsageTracker()),
      if (images != null) tutorImageServiceProvider.overrideWithValue(images),
      if (solver != null) solverServiceProvider.overrideWithValue(solver),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('TutorReplyEngine', () {
    const engine = TutorReplyEngine();

    test('greets warmly without scan context', () {
      final response = engine.greeting(null);
      expect(response.text.toLowerCase(), contains('numi'));
      expect(response.suggestions, isNotEmpty);
    });

    test('greeting is aware of a scanned problem', () {
      final response = engine.greeting(
        const TutorLaunchContext(
          questionLatex: r'2x + 5 = 13',
          answerLatex: r'x = 4',
          equationType: 'Linear Equation',
        ),
        mode: TutorMode.showSolution,
      );
      expect(response.text, contains('Linear Equation'));
      expect(response.text, contains(r'x = 4'));
    });

    test('the greeting withholds the answer until a mode is chosen', () {
      const context = TutorLaunchContext(
        questionLatex: r'2x + 5 = 13',
        answerLatex: r'x = 4',
        equationType: 'Linear Equation',
      );
      // No mode → the picker is next, and nothing may leak before the student
      // has said whether they want the answer at all.
      final undecided = engine.greeting(context);
      expect(undecided.text, isNot(contains(r'x = 4')));

      // Hint mode is a promise: the answer stays withheld even now.
      final hint = engine.greeting(context, mode: TutorMode.hint);
      expect(hint.text, isNot(contains(r'x = 4')));
      expect(hint.text, contains('Linear Equation'));
    });

    test('hint mode refuses to hand over the answer when asked outright', () {
      final response = engine.reply(
        'Just tell me the answer.',
        history: const [],
        mode: TutorMode.hint,
      );
      // …and always offers the way out, so refusing never dead-ends a student.
      expect(response.suggestions, contains(SuggestionAction.showSolution));
    });

    test('each mode offers its own follow-up chips', () {
      const context = TutorLaunchContext(
        questionLatex: r'2x + 5 = 13',
        equationType: 'Linear Equation',
      );
      expect(
        engine.greeting(context, mode: TutorMode.solveTogether).suggestions,
        contains(SuggestionAction.nextStep),
      );
      expect(
        engine.greeting(context, mode: TutorMode.teachMe).suggestions,
        contains(SuggestionAction.giveExample),
      );
    });

    test('"create a quiz" returns a quiz card', () {
      final response = engine.reply('Can you create a quiz?', history: const []);
      expect(response.card, isA<QuizCard>());
      final quiz = (response.card! as QuizCard).question;
      expect(quiz.options.where((o) => o.isCorrect), hasLength(1));
    });

    test('"practice" returns a practice card', () {
      final response =
          engine.reply('Give me a practice question.', history: const []);
      expect(response.card, isA<PracticeCard>());
    });

    test('"why" explains inverse operations', () {
      final response =
          engine.reply('But why do we subtract 5?', history: const []);
      expect(response.text.toLowerCase(), contains('opposite operation'));
    });

    test('"explain like I\'m 10" uses the wall analogy', () {
      final response = engine.reply("Explain like I'm 10.", history: const []);
      expect(response.text.toLowerCase(), contains('wall'));
    });

    test('examples rotate as more are requested', () {
      final first = engine.reply('Give me an example.', history: const []);
      const priorAsk = TutorMessage.user(id: 0, text: 'give me an example');
      final second = engine.reply('Another example?', history: const [priorAsk]);

      final firstLatex = (first.card! as PracticeCard).prompt.questionLatex;
      final secondLatex = (second.card! as PracticeCard).prompt.questionLatex;
      expect(firstLatex, isNot(secondLatex));
    });

    test('unknown input falls back to an encouraging menu', () {
      final response = engine.reply('purple monkey', history: const []);
      expect(response.suggestions, isNotEmpty);
      expect(response.card, isNull);
    });

    test('greets on a real hello but not on substrings like "this"', () {
      final greeting = engine.reply('hey Matheasy!', history: const []);
      expect(greeting.text.toLowerCase(), contains('great to see you'));

      // "this" contains "hi" — must NOT be treated as a greeting.
      final notGreeting =
          engine.reply('What is this equation about?', history: const []);
      expect(notGreeting.text.toLowerCase(), isNot(contains('great to see')));
    });
  });

  group('TutorChatController', () {
    test('start seeds a single greeting on an empty session', () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(null);

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages, hasLength(1));
      expect(session.messages.single.role, TutorRole.assistant);
      expect(session.isTyping, isFalse);
    });

    test('start with scan context adds a system notice then greeting',
        () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(
            const TutorLaunchContext(
              questionLatex: r'2x + 5 = 13',
              equationType: 'Linear Equation',
            ),
          );

      final messages = container.read(tutorChatControllerProvider).messages;
      expect(messages.first.role, TutorRole.system);
      expect(messages[1].role, TutorRole.assistant);
    });

    test('seed message auto-sends as the first user turn', () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(
            const TutorLaunchContext(seedMessage: 'Create a quiz for me.'),
          );

      final messages = container.read(tutorChatControllerProvider).messages;
      // greeting, user seed, assistant reply (with quiz card)
      expect(messages, hasLength(3));
      expect(messages[1].role, TutorRole.user);
      expect(messages[1].text, 'Create a quiz for me.');
      expect(messages[2].card, isA<QuizCard>());
    });

    test('a seeded launch starts a fresh thread over a persisted one',
        () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('Teach me geometry.'); // 3 persisted messages

      // Re-opening from a tapped suggested prompt must NOT append onto the old
      // (unrelated) thread — it starts fresh.
      await controller.start(
        const TutorLaunchContext(seedMessage: 'Create a quiz for me.'),
      );

      final messages = container.read(tutorChatControllerProvider).messages;
      expect(messages, hasLength(3)); // greeting + seed + reply, not 6
      expect(messages[1].text, 'Create a quiz for me.');
      expect(messages[2].card, isA<QuizCard>());
    });

    test('send appends user + assistant turns and clears typing', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('Why do we subtract 5?');

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages, hasLength(3)); // greeting + user + assistant
      expect(session.messages[1].isUser, isTrue);
      expect(session.messages[2].isAssistant, isTrue);
      expect(session.isTyping, isFalse);
    });

    test('empty/whitespace messages are ignored', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('   ');
      expect(container.read(tutorChatControllerProvider).messages, hasLength(1));
    });

    test('loadConversation replaces the thread', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      const convo = TutorConversation(
        id: 'x',
        title: 'Saved chat',
        preview: '…',
        icon: Icons.calculate_rounded,
        messages: [
          TutorMessage.user(id: 0, text: 'Hello'),
          TutorMessage(id: 1, role: TutorRole.assistant, text: 'Hi there!'),
        ],
      );
      controller.loadConversation(convo);

      final messages = container.read(tutorChatControllerProvider).messages;
      expect(messages, hasLength(2));
      expect(messages.first.text, 'Hello');
    });

    test('reset restarts with a fresh greeting', () async {
      final container = _instantContainer();
      final controller =
          container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      await controller.send('Give me a quiz');
      controller.reset();

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages, hasLength(1));
      expect(session.messages.single.role, TutorRole.assistant);
    });

    test('a problem with no chosen mode opens the picker', () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(
            const TutorLaunchContext(
              questionLatex: r'2x + 5 = 13',
              equationType: 'Linear Equation',
            ),
          );

      final session = container.read(tutorChatControllerProvider);
      expect(session.awaitingModeChoice, isTrue);
      // The greeting must not pre-empt the choice with a chip row.
      expect(session.messages.last.suggestions, isEmpty);
    });

    test('a launch that names a mode skips the picker', () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(
            const TutorLaunchContext(
              questionLatex: r'2x + 5 = 13',
              equationType: 'Linear Equation',
              mode: TutorMode.teachMe,
            ),
          );

      final session = container.read(tutorChatControllerProvider);
      expect(session.awaitingModeChoice, isFalse);
      expect(session.mode, TutorMode.teachMe);
    });

    test('a seeded launch skips the picker — the student already asked',
        () async {
      final container = _instantContainer();
      await container.read(tutorChatControllerProvider.notifier).start(
            const TutorLaunchContext(
              questionLatex: r'2x + 5 = 13',
              equationType: 'Linear Equation',
              seedMessage: 'Why do we subtract 5?',
            ),
          );

      expect(
        container.read(tutorChatControllerProvider).awaitingModeChoice,
        isFalse,
      );
    });

    test('chooseMode posts the choice as a turn and answers in that mode',
        () async {
      final container = _instantContainer();
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(
        const TutorLaunchContext(
          questionLatex: r'2x + 5 = 13',
          equationType: 'Linear Equation',
        ),
      );
      await controller.chooseMode(TutorMode.hint, 'Just a hint');

      final session = container.read(tutorChatControllerProvider);
      expect(session.mode, TutorMode.hint);
      expect(session.awaitingModeChoice, isFalse);
      expect(session.messages[2].isUser, isTrue);
      expect(session.messages[2].text, 'Just a hint');
    });

    test('"Show the solution" switches mode as well as sending', () async {
      final container = _instantContainer();
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      controller.setMode(TutorMode.hint);

      await controller.sendAction(
        SuggestionAction.showSolution,
        'Show me the full solution.',
      );

      expect(
        container.read(tutorChatControllerProvider).mode,
        TutorMode.showSolution,
      );
    });

    test('"I don\'t understand" escalates the help level', () async {
      final container = _instantContainer();
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);
      expect(container.read(tutorChatControllerProvider).memory.helpLevel, 0);

      await controller.sendAction(
        SuggestionAction.iDontUnderstand,
        "I don't understand.",
      );

      expect(
        container.read(tutorChatControllerProvider).memory.helpLevel,
        greaterThan(0),
      );
    });

    test('a new problem clears what Numi had learned about the old one',
        () async {
      final container = _instantContainer();
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(
        const TutorLaunchContext(
          questionLatex: r'2x + 5 = 13',
          equationType: 'Linear Equation',
        ),
      );
      await controller.sendAction(
        SuggestionAction.iDontUnderstand,
        "I don't understand.",
      );
      expect(
        container.read(tutorChatControllerProvider).memory.helpLevel,
        greaterThan(0),
      );

      await controller.start(
        const TutorLaunchContext(
          questionLatex: r'x^2 - 9 = 0',
          equationType: 'Quadratic Equation',
        ),
      );

      expect(container.read(tutorChatControllerProvider).memory.helpLevel, 0);
    });
  });

  group('TutorImageMapper', () {
    test('maps a photographed problem', () {
      final read = TutorImageMapper.toRead(const {
        'kind': 'problem',
        'problem': r'  2x + 5 = 13  ',
        'note': 'Clear photo.',
        'confidence': 0.8,
      });

      expect(read.kind, TutorImageKind.problem);
      expect(read.problem, r'2x + 5 = 13');
      expect(read.hasProblem, isTrue);
      expect(read.hasWork, isFalse);
      expect(read.note, 'Clear photo.');
      expect(read.confidence, 0.8);
    });

    test('work with no legible lines is demoted to a problem', () {
      final read = TutorImageMapper.toRead(const {
        'kind': 'work',
        'problem': r'x^2 - 9 = 0',
        'work': <String>[],
      });

      expect(read.kind, TutorImageKind.problem);
    });

    test('a readable label with nothing in it is unreadable', () {
      final read = TutorImageMapper.toRead(const {
        'kind': 'problem',
        'problem': '   ',
        'note': 'Too blurry.',
      });

      expect(read.kind, TutorImageKind.unreadable);
      expect(read.kind.isReadable, isFalse);
      // The reason survives the demotion — the student still gets told why.
      expect(read.note, 'Too blurry.');
    });

    test('an unknown kind from a stale deploy is unreadable, not trusted', () {
      expect(
        TutorImageMapper.toRead(const {'kind': 'diagram', 'problem': 'x = 1'})
            .kind,
        TutorImageKind.unreadable,
      );
      expect(TutorImageMapper.toRead(const <String, dynamic>{}).kind,
          TutorImageKind.unreadable);
    });

    test('work lines are trimmed, de-blanked and capped', () {
      final read = TutorImageMapper.toRead({
        'kind': 'work',
        'work': [
          '  2x = 8  ',
          '',
          '   ',
          42, // not a string — dropped rather than stringified
          for (var i = 0; i < 20; i++) 'line $i',
        ],
      });

      expect(read.work.first, '2x = 8');
      expect(read.work, hasLength(TutorImageMapper.maxWorkLines));
      expect(read.work, isNot(contains('')));
    });

    test('confidence is clamped, and defaults when absent or junk', () {
      expect(
        TutorImageMapper.toRead(
                const {'kind': 'problem', 'problem': 'x', 'confidence': 4})
            .confidence,
        1.0,
      );
      expect(
        TutorImageMapper.toRead(
                const {'kind': 'problem', 'problem': 'x', 'confidence': -1})
            .confidence,
        0.0,
      );
      expect(
        TutorImageMapper.toRead(
                const {'kind': 'problem', 'problem': 'x', 'confidence': 'high'})
            .confidence,
        0.9,
      );
    });
  });

  group('TutorChatController.sendImage', () {
    test('a photographed problem is solved by the app, then answered',
        () async {
      final solver = _RecordingSolver();
      final container = _instantContainer(
        images: _ScriptedImageService(
          result: const TutorImageRead(
            kind: TutorImageKind.problem,
            problem: r'2x + 5 = 13',
          ),
        ),
        solver: solver,
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      final ok = await controller.sendImage(_photo, copy: _imageCopy);

      expect(ok, isTrue);
      // The golden rule: the transcription is a question to solve, never an
      // answer to repeat.
      expect(solver.seen.single.latex, r'2x + 5 = 13');

      final session = container.read(tutorChatControllerProvider);
      // greeting + the photo turn + "here's what I read" + the reply
      expect(session.messages, hasLength(4));
      expect(session.messages[1].isUser, isTrue);
      expect(session.messages[1].hasImage, isTrue);
      expect(session.messages[1].text, 'ASK_PROBLEM');
      expect(session.messages[2].role, TutorRole.system);
      expect(session.messages[2].text, 'SAW_PROBLEM');
      expect(session.messages[3].isAssistant, isTrue);
      expect(session.isTyping, isFalse);
      expect(session.context?.questionLatex, r'2x + 5 = 13');
    });

    test('a caption speaks for the student instead of the default line',
        () async {
      final container = _instantContainer(
        images: _ScriptedImageService(
          result: const TutorImageRead(
            kind: TutorImageKind.problem,
            problem: r'2x + 5 = 13',
          ),
        ),
        solver: _RecordingSolver(),
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      await controller.sendImage(
        _photo,
        copy: _imageCopy,
        caption: 'Where did I go wrong?',
      );

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages[1].text, 'Where did I go wrong?');
      expect(session.messages[1].hasImage, isTrue);
    });

    test('a photo of working keeps the problem and hands over the lines',
        () async {
      final tutor = _InstantTutorService();
      final solver = _RecordingSolver();
      final container = _instantContainer(
        tutor: tutor,
        images: _ScriptedImageService(
          result: const TutorImageRead(
            kind: TutorImageKind.work,
            work: ['2x = 8', 'x = 3'],
          ),
        ),
        solver: solver,
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(
        const TutorLaunchContext(
          questionLatex: r'2x + 5 = 13',
          equationType: 'Linear Equation',
          mode: TutorMode.solveTogether,
        ),
      );

      await controller.sendImage(_photo, copy: _imageCopy);

      // Working carries no new question, so nothing is re-solved and the
      // conversation stays on the problem it was already about.
      expect(solver.seen, isEmpty);
      expect(tutor.lastStudentWork, ['2x = 8', 'x = 3']);

      final messages = container.read(tutorChatControllerProvider).messages;
      final photo = messages.firstWhere((m) => m.hasImage);
      expect(photo.text, 'ASK_WORK');
      expect(messages[messages.length - 2].text, 'SAW_WORK');
      expect(messages.last.isAssistant, isTrue);
      expect(
        container.read(tutorChatControllerProvider).context?.questionLatex,
        r'2x + 5 = 13',
      );
    });

    test('a photo with no math in it is answered, not silently dropped',
        () async {
      final solver = _RecordingSolver();
      final container = _instantContainer(
        images: _ScriptedImageService(
          result: const TutorImageRead(
            kind: TutorImageKind.notMath,
            note: 'This looks like a photo of a cat.',
          ),
        ),
        solver: solver,
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      final ok = await controller.sendImage(_photo, copy: _imageCopy);

      expect(ok, isTrue);
      expect(solver.seen, isEmpty);
      final session = container.read(tutorChatControllerProvider);
      expect(session.messages.last.isAssistant, isTrue);
      expect(session.messages.last.text, contains('NOT_MATH'));
      expect(session.messages.last.text,
          contains('This looks like a photo of a cat.'));
      expect(session.isTyping, isFalse);
    });

    test('an unreadable photo says so', () async {
      final container = _instantContainer(
        images: _ScriptedImageService(),
        solver: _RecordingSolver(),
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      await controller.sendImage(_photo, copy: _imageCopy);

      final session = container.read(tutorChatControllerProvider);
      expect(session.messages.last.text, 'UNREADABLE');
      expect(session.isTyping, isFalse);
    });

    test('a backend failure is admitted rather than swallowed', () async {
      final container = _instantContainer(
        images: _ScriptedImageService(
          error: const BackendException('boom'),
        ),
        solver: _RecordingSolver(),
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      final ok = await controller.sendImage(_photo, copy: _imageCopy);

      expect(ok, isTrue);
      final session = container.read(tutorChatControllerProvider);
      expect(session.messages.last.text, 'FAILED');
      expect(session.isTyping, isFalse);
    });

    test('a spent quota reports back so the caller can open the paywall',
        () async {
      final container = _instantContainer(
        images: _ScriptedImageService(
          error: const BackendException('out of scans',
              code: 'resource-exhausted'),
        ),
        solver: _RecordingSolver(),
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      final ok = await controller.sendImage(_photo, copy: _imageCopy);

      expect(ok, isFalse);
      final session = container.read(tutorChatControllerProvider);
      // No "I couldn't read it" — that would blame the photo for a paywall.
      expect(session.messages.last.isUser, isTrue);
      expect(session.messages.last.hasImage, isTrue);
      expect(session.isTyping, isFalse);
    });

    test('an empty image is a no-op, and never reaches the backend', () async {
      final images = _ScriptedImageService();
      final container =
          _instantContainer(images: images, solver: _RecordingSolver());
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      final ok = await controller.sendImage(Uint8List(0), copy: _imageCopy);

      expect(ok, isTrue);
      expect(images.calls, 0);
      expect(container.read(tutorChatControllerProvider).messages, hasLength(1));
    });
  });

  group('TutorChatController streaming (spec Part 18)', () {
    test('the reply appears as it is written, in one growing bubble', () async {
      final tutor = _StreamingTutorService(
        deltas: const ['Subtract ', '5 from ', 'both sides.'],
      );
      final container = _instantContainer(tutor: tutor);
      final controller = container.read(tutorChatControllerProvider.notifier);
      tutor.read = () => container.read(tutorChatControllerProvider);
      await controller.start(null);

      await controller.send('how do I start?');

      // One bubble per delta — the same one, growing.
      expect(tutor.snapshots, hasLength(3));
      expect(
        [for (final s in tutor.snapshots) s.messages.last.text],
        ['Subtract ', 'Subtract 5 from ', 'Subtract 5 from both sides.'],
      );
      final ids = {for (final s in tutor.snapshots) s.messages.last.id};
      expect(ids, hasLength(1), reason: 'the reply must not restack per delta');

      // The three dots give way the moment there are words to read — but the
      // turn is still in flight, so the composer stays closed.
      expect(
        [for (final s in tutor.snapshots) s.isThinking],
        everyElement(isFalse),
      );
      expect(
        [for (final s in tutor.snapshots) s.isTyping],
        everyElement(isTrue),
      );
      final session = container.read(tutorChatControllerProvider);
      expect(session.isTyping, isFalse);
      expect(session.streamingId, isNull);
    });

    test('a second question can not interleave with a reply mid-sentence',
        () async {
      final tutor = _StreamingTutorService(deltas: const ['One ', 'two ']);
      final container = _instantContainer(tutor: tutor);
      final controller = container.read(tutorChatControllerProvider.notifier);
      var asks = 0;
      tutor.read = () {
        if (++asks == 1) unawaited(controller.send('are you there?'));
        return container.read(tutorChatControllerProvider);
      };
      await controller.start(null);

      await controller.send('hello');
      await Future<void>.delayed(Duration.zero);

      final messages = container.read(tutorChatControllerProvider).messages;
      // greeting + "hello" + the reply. The interrupting question never posted.
      expect(messages, hasLength(3));
      expect(messages.where((m) => m.isUser).single.text, 'hello');
    });

    test('the finished response replaces the streamed text in place', () async {
      final tutor = _StreamingTutorService(
        deltas: const ['Half ', 'an answ'],
        finalText: 'Half an answer, then the whole one.',
        suggestions: const [
          SuggestionAction.giveExample,
          SuggestionAction.tellMeWhy,
        ],
      );
      final container = _instantContainer(tutor: tutor);
      final controller = container.read(tutorChatControllerProvider.notifier);
      tutor.read = () => container.read(tutorChatControllerProvider);
      await controller.start(null);

      await controller.send('why?');

      final messages = container.read(tutorChatControllerProvider).messages;
      // greeting + the student's turn + exactly one assistant reply.
      expect(messages, hasLength(3));
      expect(messages.last.text, 'Half an answer, then the whole one.');
      expect(messages.last.id, tutor.snapshots.last.messages.last.id);
      // The chips only exist on the authoritative response, so this is the
      // proof that the streamed preview was replaced and not merely appended to.
      expect(messages.last.suggestions, [
        SuggestionAction.giveExample,
        SuggestionAction.tellMeWhy,
      ]);
    });

    test('a stream that drops keeps the words and admits the failure', () async {
      final tutor = _StreamingTutorService(
        deltas: const ['Start by isol'],
        error: const BackendException('connection dropped',
            code: 'unavailable'),
      );
      final container = _instantContainer(tutor: tutor);
      final controller = container.read(tutorChatControllerProvider.notifier);
      await controller.start(null);

      await controller.send('help');

      final session = container.read(tutorChatControllerProvider);
      // The half-sentence stays on screen — taking back words the student has
      // already read is worse than letting them see where it stopped.
      expect(session.messages[session.messages.length - 2].text,
          'Start by isol');
      // …followed by an honest admission that owns the failure rather than
      // blaming the student's connection for our outage.
      expect(session.messages.last.text, contains("couldn't get through"));
      expect(session.messages.last.text, isNot(contains('connection')));
      expect(session.isTyping, isFalse);
    });

    test('a reply streaming into a thread the student left is dropped',
        () async {
      final tutor = _StreamingTutorService(deltas: const ['One ', 'two ']);
      final container = _instantContainer(tutor: tutor);
      final controller = container.read(tutorChatControllerProvider.notifier);
      // Start a new conversation part-way through the answer.
      var deltas = 0;
      tutor.read = () {
        if (++deltas == 1) controller.reset();
        return container.read(tutorChatControllerProvider);
      };
      await controller.start(null);

      await controller.send('hello');

      final session = container.read(tutorChatControllerProvider);
      // Just the fresh greeting: no words from the abandoned turn leaked in.
      expect(session.messages, hasLength(1));
      expect(session.messages.single.isAssistant, isTrue);
      expect(session.isTyping, isFalse);
    });

    test('a photo turn streams too, and still hands over the working',
        () async {
      final tutor = _StreamingTutorService(deltas: const ['Line ', 'two.']);
      final container = _instantContainer(
        tutor: tutor,
        images: _ScriptedImageService(
          result: const TutorImageRead(
            kind: TutorImageKind.work,
            work: ['2x = 8', 'x = 3'],
          ),
        ),
        solver: _RecordingSolver(),
      );
      final controller = container.read(tutorChatControllerProvider.notifier);
      tutor.read = () => container.read(tutorChatControllerProvider);
      await controller.start(null);

      await controller.sendImage(_photo, copy: _imageCopy);

      expect(tutor.snapshots.first.messages.last.text, 'Line ');
      expect(tutor.lastStudentWork, ['2x = 8', 'x = 3']);
      final session = container.read(tutorChatControllerProvider);
      expect(session.messages.last.text, 'Line two.');
      expect(session.isTyping, isFalse);
    });
  });

  group('TutorMemory', () {
    test('a struggling turn escalates help, a confident one resets it', () {
      const struggling = TutorTurnMeta(
        understanding: TutorUnderstanding.struggling,
        conceptsCovered: ['inverse operations'],
      );
      final after = const TutorMemory().fold(struggling).fold(struggling);
      expect(after.helpLevel, 2);
      expect(after.conceptsCovered, contains('inverse operations'));

      final recovered = after.fold(
        const TutorTurnMeta(understanding: TutorUnderstanding.confident),
      );
      expect(recovered.helpLevel, 0);
    });

    test('help level is capped so Numi stops escalating past showing a step',
        () {
      var memory = const TutorMemory();
      for (var i = 0; i < 8; i++) {
        memory = memory.fold(
          const TutorTurnMeta(understanding: TutorUnderstanding.struggling),
        );
      }
      expect(memory.helpLevel, 3);
    });

    test('a concept the student then gets right becomes a strength', () {
      final memory = const TutorMemory().fold(
        const TutorTurnMeta(
          understanding: TutorUnderstanding.confident,
          conceptsCovered: ['balancing equations'],
        ),
      );
      expect(memory.strengths, contains('balancing equations'));
    });
  });

  group('TutorHome content', () {
    test('provider yields the full mock landing content', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final data = container.read(tutorHomeProvider);
      expect(data.suggestedPrompts, hasLength(5));
      expect(data.categories, hasLength(7));
      expect(data.quickActions, hasLength(4));
      expect(data.recentConversations, hasLength(3));
    });
  });

  group('Tutor widgets', () {
    testWidgets('home renders the hero and a category', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: TutorScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // stagger settle

      expect(find.text('How can I help today?'), findsOneWidget);
      expect(find.text('Try asking'), findsOneWidget);

      // Categories render further down — scroll the page to reveal one.
      await tester.scrollUntilVisible(
        find.text('Algebra'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Algebra'), findsOneWidget);
    });

    testWidgets('chat greets, then answers a sent message', (tester) async {
      // Sending a message records tutor usage for progress, which needs prefs.
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            tutorServiceProvider
                .overrideWithValue(_InstantTutorService()),
          ],
          child: const MaterialApp(home: TutorChatScreen()),
        ),
      );
      await tester.pump(); // run the post-frame start()
      await tester.pump();

      expect(find.textContaining('math coach'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Why do we subtract 5?');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('opposite operation'), findsOneWidget);
    });

    testWidgets('quiz card reveals feedback after answering', (tester) async {
      const question = QuizQuestion(
        prompt: 'Solve for x',
        promptLatex: r'2x = 6',
        options: [
          QuizOption(text: '2'),
          QuizOption(text: '3', isCorrect: true),
        ],
        explanation: 'Divide both sides by 2 to get x = 3.',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: Center(child: TutorQuizCard(question))),
        ),
      );
      await tester.pump();

      // Explanation is hidden until an option is chosen.
      expect(find.textContaining('Divide both sides'), findsNothing);

      await tester.tap(find.text('3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.textContaining('Correct'), findsOneWidget);
      expect(find.textContaining('Divide both sides'), findsOneWidget);
    });

    // Spec Parts 7–8: Numi points at the maths while she talks about it.
    testWidgets('an assistant turn shows the equation it is pointing at',
        (tester) async {
      const message = TutorMessage(
        id: 1,
        role: TutorRole.assistant,
        text: 'Look at the middle term.',
        focus: TutorFocus(
          latex: 'x^2 + 8x + 4 = 0',
          caption: 'the coefficient of x',
          highlights: [MathHighlight(text: '8x', role: MathRole.operation)],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // Numi breathes forever inside the assistant bubble, so an animating
          // tree never settles. Reduced motion holds her still — the same
          // escape hatch MatheasyLoader's test uses. copyWith, not a bare
          // MediaQueryData: the bubble sizes itself off the screen width.
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: TutorMessageView(
                  message: message,
                  onSuggestion: (_) {},
                  onPracticeStart: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('the coefficient of x'), findsOneWidget);
      expect(find.byType(HighlightedMath), findsOneWidget);
      // The caption wears the highlight's own colour — that is how the colour
      // vocabulary is taught without ever showing a legend.
      final caption = tester.widget<Text>(find.text('the coefficient of x'));
      expect(
        caption.style?.color,
        MathRole.operation.color(AppSemanticColors.light, isDark: false),
      );
    });

    // Spec Part 9: when the maths has a picture, it appears under the equation
    // it belongs to — not on another screen, and not instead of the words.
    testWidgets('an assistant turn draws the maths it is pointing at',
        (tester) async {
      const message = TutorMessage(
        id: 1,
        role: TutorRole.assistant,
        text: 'Three of the four parts are shaded.',
        focus: TutorFocus(
          latex: r'\frac{3}{4}',
          caption: 'three quarters',
          highlights: [MathHighlight(text: '3', role: MathRole.known)],
          sketch: VisualConcept(
            kind: VisualConceptKind.fractionBar,
            caption: 'three quarters',
            params: {'numerator': 3, 'denominator': 4},
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: TutorMessageView(
                  message: message,
                  onSuggestion: (_) {},
                  onPracticeStart: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TutorSketchView), findsOneWidget);
      expect(find.byType(HighlightedMath), findsOneWidget);
      expect(find.text('Three of the four parts are shaded.'), findsOneWidget);
    });

    testWidgets('a focus with no drawing shows the equation alone',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: TutorMessageView(
                  message: const TutorMessage(
                    id: 1,
                    role: TutorRole.assistant,
                    text: 'Look at the middle term.',
                    focus: TutorFocus(
                      latex: 'x^2 + 8x + 4 = 0',
                      caption: 'the coefficient of x',
                      highlights: [
                        MathHighlight(text: '8x', role: MathRole.operation),
                      ],
                    ),
                  ),
                  onSuggestion: (_) {},
                  onPracticeStart: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HighlightedMath), findsOneWidget);
      expect(find.byType(TutorSketchView), findsNothing);
    });

    testWidgets('a turn with no focus renders exactly as before', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: Scaffold(
                body: TutorMessageView(
                  message: const TutorMessage(
                    id: 1,
                    role: TutorRole.assistant,
                    text: 'Nice work.',
                  ),
                  onSuggestion: (_) {},
                  onPracticeStart: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HighlightedMath), findsNothing);
    });

    testWidgets('a scanned problem opens on the mode picker, and choosing one '
        'answers in that mode', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            tutorServiceProvider
                .overrideWithValue(_InstantTutorService()),
          ],
          child: const MaterialApp(
            home: TutorChatScreen(
              launchContext: TutorLaunchContext(
                questionLatex: r'2x + 5 = 13',
                equationType: 'Linear Equation',
              ),
            ),
          ),
        ),
      );
      await tester.pump(); // run the post-frame start()
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // entrance settle

      expect(find.text('How would you like to learn this?'), findsOneWidget);
      expect(find.text('Just a hint'), findsOneWidget);
      expect(find.text('Quiz me'), findsOneWidget);
      // The answer stays behind the choice.
      expect(find.textContaining('x = 4'), findsNothing);

      await tester.tap(find.text('Just a hint'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The picker is gone and the choice reads as the student's own turn.
      expect(find.text('How would you like to learn this?'), findsNothing);
      expect(find.text('Just a hint'), findsOneWidget);
    });
  });
}
