import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/backend/functions_client.dart';
import '../../../core/monitoring/logging_service.dart';
import '../../../core/security/rate_limit_result.dart';
import '../../../core/security/rate_limit_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../analytics/application/analytics_service.dart';
import '../../analytics/domain/analytics_event.dart';
import '../../result/application/solver_service.dart';
import '../../scan/application/functions_scanner_service.dart';
import '../../scan/domain/detected_equation.dart';
import '../../scan/domain/scan_source.dart';
import '../../subscription/application/usage_controller.dart';
import '../domain/tutor_context_builder.dart';
import '../domain/tutor_models.dart';
import 'tutor_image_service.dart';
import 'tutor_service.dart';

part 'tutor_controller.g.dart';

/// Supplies the Tutor home's content: suggested prompts, recent conversations,
/// learning categories and quick actions.
///
/// Entirely mock today (see [TutorHomeContent]); a later stage swaps the source
/// without touching the UI.
@riverpod
TutorHomeData tutorHome(Ref ref) => TutorHomeContent.build();

/// Drives the live chat conversation with Numi.
///
/// Holds the running [TutorSession] and orchestrates the send → typing → reply
/// loop through the [TutorService]. Kept alive so the conversation survives
/// navigating away from and back to the chat ("continue conversations"); the
/// screen calls [start] once per open to seed a greeting or auto-send a prompt.
@Riverpod(keepAlive: true)
class TutorChatController extends _$TutorChatController {
  int _seq = 0;

  /// Bumped whenever the thread is replaced wholesale (a new conversation, a
  /// restored one, a fresh seeded launch). A reply that was streaming into the
  /// old thread compares this and stops, rather than writing its words into a
  /// conversation they don't belong to.
  int _thread = 0;

  int _nextId() => _seq++;

  @override
  TutorSession build() => const TutorSession();

  /// Reads the active tutor implementation lazily so provider overrides (real
  /// AI, or a test double) are always honored.
  TutorService get _service => ref.read(tutorServiceProvider);

  /// Called once when the chat screen opens. Seeds a greeting on an empty
  /// session, announces a newly-scanned problem, and/or auto-sends a prompt
  /// carried by [context].
  ///
  /// A *seeded* launch (a tapped suggested prompt or category) always begins a
  /// fresh topic thread — even though this controller is kept alive — so a
  /// starter never appends onto, or duplicates a turn in, an unrelated
  /// persisted conversation. A plain "Ask Numi" open (no seed) continues the
  /// existing thread.
  Future<void> start(TutorLaunchContext? context) async {
    unawaited(
        ref.read(analyticsServiceProvider).logEvent(AnalyticsEvent.tutorOpened()));
    final seed = context?.seedMessage?.trim();
    final hasSeed = seed != null && seed.isNotEmpty;

    if (hasSeed && state.messages.isNotEmpty) {
      _seq = 0;
      _thread++;
      state = const TutorSession();
    }

    // A launch that carries a problem but no chosen mode opens with the picker
    // ("How would you like to learn this?", spec Part 20) — but not when the
    // caller seeded a question, since the student has already said what they
    // want and a picker would just be in the way.
    final asksMode = context != null && context.needsModeChoice && !hasSeed;
    final mode = context?.mode ?? (asksMode ? null : state.mode);

    if (state.isEmpty) {
      final messages = <TutorMessage>[];
      if (context != null && context.hasScan) {
        messages.add(
          TutorMessage.system(
            id: _nextId(),
            text: context.hasVisualStep
                ? 'Numi can see the visual step you tapped'
                : 'Numi can see your scanned problem',
          ),
        );
      }
      final greeting = _service.greeting(context, mode: mode);
      messages.add(_assistantFrom(greeting));
      state = state.copyWith(
        messages: messages,
        context: context,
        mode: mode ?? TutorMode.fallback,
        awaitingModeChoice: asksMode,
      );
    } else if (context != null &&
        context.hasScan &&
        context != state.context) {
      // Re-entered with a different scanned problem (or a different visual
      // step of the same one) — announce and re-greet. A new problem resets what
      // Numi "knows": the struggles and strengths were about the old one.
      final greeting = _service.greeting(context, mode: mode);
      state = state.copyWith(
        context: context,
        mode: mode ?? TutorMode.fallback,
        memory: const TutorMemory(),
        awaitingModeChoice: asksMode,
        messages: [
          ...state.messages,
          TutorMessage.system(
            id: _nextId(),
            text: context.hasVisualStep
                ? 'Now looking at the step you tapped'
                : 'Now looking at your new problem',
          ),
          _assistantFrom(greeting),
        ],
      );
    }

    if (hasSeed) {
      await send(seed);
    }
  }

  /// The student answered "How would you like to learn this?".
  ///
  /// [message] is the mode's localized label, posted as the student's own turn
  /// so the choice reads as part of the conversation and Numi replies to it in
  /// the newly-selected mode.
  Future<void> chooseMode(TutorMode mode, String message) async {
    state = state.copyWith(mode: mode, awaitingModeChoice: false);
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.tutorModeSelected(mode.id)));
    await send(message);
  }

  /// Switches teaching mode mid-conversation without sending a turn — used by
  /// the mode switcher in the app bar. The next message is answered in [mode].
  void setMode(TutorMode mode) {
    if (state.mode == mode && !state.awaitingModeChoice) return;
    state = state.copyWith(mode: mode, awaitingModeChoice: false);
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.tutorModeSelected(mode.id)));
  }

  /// Sends a free-text [rawText] turn and appends Numi's reply. Ignored while
  /// Numi is already thinking, so a double-tap can't interleave turns.
  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || state.isTyping) return;

    // Client-side abuse guard (server enforcement is authoritative).
    final limit = ref
        .read(rateLimitServiceProvider)
        .check(RateLimitedAction.tutorMessage);
    if (limit.isLimited) {
      LoggingService.warning('Tutor message rate-limited: ${limit.reason}');
      return;
    }

    // Count every user message against the free-tier AI tutor quota — the single
    // choke point, so seeded prompts and quick replies are all captured.
    ref.read(usageControllerProvider.notifier).recordTutorMessage();
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.tutorMessageSent()));

    state = state.copyWith(
      messages: [
        ...state.messages,
        TutorMessage.user(id: _nextId(), text: text),
      ],
      isTyping: true,
    );

    try {
      await _ask(text);
    } catch (error, stackTrace) {
      // Never leave the composer stuck in "typing" — surface a friendly,
      // retryable message and always clear the typing state.
      LoggingService.error('Tutor reply failed',
          error: error, stackTrace: stackTrace);
      _appendAssistant(
        "Sorry — I couldn't reach the tutor just now. Please check your "
        'connection and try again.',
      );
    }
  }

  /// Sends a photo the student attached in chat (spec Parts 2 and 12).
  ///
  /// The orchestration is what keeps this golden-rule-clean:
  ///
  /// 1. `tutorImage` **transcribes only** — it never solves and never judges.
  /// 2. A transcribed question goes through the app's own deterministic
  ///    [SolverService], so a problem photographed in chat is verified exactly
  ///    like one scanned from the scanner tab.
  /// 3. Transcribed working is checked *server-side against that verified
  ///    solution* and Numi is handed the verdict as a fact to narrate.
  ///
  /// Nothing here is silent: a photo with no math, or one that couldn't be made
  /// out, produces a specific honest reply rather than a dead end.
  ///
  /// Returns false when the student's scan allowance is gone server-side, so the
  /// caller can open the paywall instead of pretending the read failed.
  Future<bool> sendImage(
    Uint8List imageBytes, {
    required TutorImageCopy copy,
    ScanSource source = ScanSource.gallery,
    String caption = '',
  }) async {
    if (imageBytes.isEmpty || state.isTyping) return true;

    // Client-side abuse guard (server enforcement is authoritative).
    final limit = ref
        .read(rateLimitServiceProvider)
        .check(RateLimitedAction.tutorMessage);
    if (limit.isLimited) {
      LoggingService.warning('Tutor image rate-limited: ${limit.reason}');
      return true;
    }

    // A photo costs a tutor message like any other turn; the paid Vision read it
    // triggers is metered as a scan by the caller, which owns that gate.
    ref.read(usageControllerProvider.notifier).recordTutorMessage();
    unawaited(ref
        .read(analyticsServiceProvider)
        .logEvent(AnalyticsEvent.tutorMessageSent()));

    final caption0 = caption.trim();
    final photoId = _nextId();
    state = state.copyWith(
      messages: [
        ...state.messages,
        TutorMessage.user(id: photoId, text: caption0, image: imageBytes),
      ],
      isTyping: true,
    );

    final TutorImageRead read;
    try {
      read = await ref
          .read(tutorImageServiceProvider)
          .read(imageBytes, caption: caption0);
    } catch (error, stackTrace) {
      LoggingService.error('Tutor image read failed',
          error: error, stackTrace: stackTrace);
      if (error is BackendException && error.isQuotaExceeded) {
        // Not a failure to explain away — the student is out of scans. Say
        // nothing and let the caller show them why.
        state = state.copyWith(isTyping: false);
        return false;
      }
      _appendAssistant(copy.failed);
      return true;
    }

    // "Never silently fail": no math, or nothing legible, still gets a real
    // answer — plus whatever the read could tell us about why.
    if (!read.kind.isReadable) {
      final base = read.kind == TutorImageKind.notMath
          ? copy.notMath
          : copy.unreadable;
      _appendAssistant(read.note.isEmpty ? base : '$base\n\n${read.note}');
      return true;
    }

    final isWork = read.kind == TutorImageKind.work;
    // Solve the transcribed question with the app's own engine. A photo of only
    // working keeps whatever problem the conversation was already about.
    final launch = read.hasProblem
        ? await _launchFor(read.problem, source)
        : state.context;

    // Show what was read *before* the reply lands, so the student can see the
    // photo was understood — and can correct a misread instead of arguing with
    // an answer to the wrong question.
    final notice = isWork ? copy.sawWork : copy.sawProblem;
    final askText = caption0.isNotEmpty
        ? caption0
        : (isWork ? copy.askWork : copy.askProblem);
    state = state.copyWith(
      context: launch,
      // A photographed question is a new problem: what Numi had learned about
      // the student was about the old one (mirrors [start]).
      memory: read.hasProblem && !isWork ? const TutorMemory() : state.memory,
      messages: [
        for (final m in state.messages)
          // Fill in the turn posted on the student's behalf, so their own
          // history reads as something they actually said.
          if (m.id == photoId && caption0.isEmpty)
            TutorMessage.user(id: m.id, text: askText, image: m.image)
          else
            m,
        TutorMessage.system(
          id: _nextId(),
          text: read.note.isEmpty ? notice : '$notice — ${read.note}',
        ),
      ],
    );

    try {
      // `read.work` is checked deterministically server-side before Numi ever
      // sees it.
      await _ask(askText, studentWork: read.work);
    } catch (error, stackTrace) {
      LoggingService.error('Tutor reply failed after photo',
          error: error, stackTrace: stackTrace);
      _appendAssistant(copy.failed);
    }
    return true;
  }

  /// Asks Numi about [userText] and lands the answer, rendering the reply as it
  /// is written (spec Part 18).
  ///
  /// The streamed words are only ever a *preview*: the finished [TutorResponse]
  /// replaces them in the same bubble, so the verified card and the suggestion
  /// chips arrive with text that is authoritative rather than partial. A service
  /// that streams nothing simply appends, exactly as before.
  ///
  /// Throws whatever the service throws — each caller apologizes in its own
  /// words.
  Future<void> _ask(String userText, {List<String> studentWork = const []}) async {
    final live = _LiveReply(_thread);
    final response = await _service.reply(
      userText,
      history: state.messages,
      context: state.context,
      mode: state.mode,
      memory: state.memory,
      studentWork: studentWork,
      onDelta: (delta) => _stream(live, delta),
    );

    final id = live.id;
    if (id == null) {
      state = state.copyWith(
        messages: [...state.messages, _assistantFrom(response)],
        // Fold this turn's read of the student forward, so the next turn opens
        // knowing what's been covered and how much help to carry (Parts 4/10).
        memory: state.memory.fold(response.meta),
        isTyping: false,
      );
      return;
    }

    // The words were streamed into a thread the student has since left; the
    // reply belongs to a conversation that is no longer on screen.
    if (live.thread != _thread) {
      state = state.copyWith(isTyping: false, clearStreaming: true);
      return;
    }

    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == id) _assistantFrom(response, id: id) else m,
      ],
      memory: state.memory.fold(response.meta),
      isTyping: false,
      clearStreaming: true,
    );
  }

  /// One piece of a streaming reply. The first delta turns the typing indicator
  /// into a real bubble; every later one grows it.
  ///
  /// `isTyping` deliberately stays true throughout: Numi is still answering, so
  /// the composer stays closed and a second question can't interleave with the
  /// turn in flight. It is `streamingId` that stands the three dots down.
  void _stream(_LiveReply live, String delta) {
    if (live.thread != _thread) return;
    live.write(delta);
    final id = live.id;
    if (id == null) {
      final newId = _nextId();
      live.id = newId;
      state = state.copyWith(
        messages: [
          ...state.messages,
          TutorMessage(id: newId, role: TutorRole.assistant, text: live.text),
        ],
        streamingId: newId,
      );
      return;
    }
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.id == id)
            TutorMessage(id: id, role: TutorRole.assistant, text: live.text)
          else
            m,
      ],
    );
  }

  /// Solves [problemLatex] with the app's deterministic solver and wraps the
  /// verified result as launch context.
  ///
  /// A solve that fails or can't be verified still produces context — just
  /// without an answer in it. `TutorContextBuilder` drops the answer whenever
  /// the result isn't verified, so Numi teaches the method and never asserts a
  /// number the app couldn't stand behind.
  Future<TutorLaunchContext?> _launchFor(
    String problemLatex,
    ScanSource source,
  ) async {
    final equation = DetectedEquation(
      latex: problemLatex,
      confidence: 1,
      source: source,
      kind: FunctionsScannerService.inferKind(problemLatex),
    );
    try {
      final result = await ref.read(solverServiceProvider).solve(equation);
      return TutorLaunchContext(
        problem: TutorContextBuilder.fromResult(result, source: 'photo'),
        mode: state.mode,
      );
    } catch (error, stackTrace) {
      LoggingService.error('Solve for tutor photo failed',
          error: error, stackTrace: stackTrace);
      return TutorLaunchContext(
        problem: TutorProblemContext(
          questionLatex: problemLatex,
          source: 'photo',
        ),
        mode: state.mode,
      );
    }
  }

  /// Appends an assistant turn and ends the turn in flight.
  ///
  /// Anything already streamed stays where it is: a half-sentence the student
  /// has read is theirs, and pulling it off screen to apologize would lose the
  /// part that did arrive.
  void _appendAssistant(String text) {
    state = state.copyWith(
      messages: [
        ...state.messages,
        TutorMessage(id: _nextId(), role: TutorRole.assistant, text: text),
      ],
      isTyping: false,
      clearStreaming: true,
    );
  }

  /// Sends the localized [message] behind a tapped suggestion chip.
  ///
  /// Two chips do more than talk: "Show the solution" is the escape hatch out of
  /// a no-answer mode, and "I don't understand" is a struggle signal the student
  /// sent directly — it escalates the help level without waiting for the model
  /// to infer it (Parts 4 and 5).
  Future<void> sendAction(SuggestionAction action, String message) async {
    final target = action.switchesTo;
    if (target != null && target != state.mode) setMode(target);
    if (action == SuggestionAction.iDontUnderstand) {
      state = state.copyWith(memory: state.memory.struggling());
    }
    await send(message);
  }

  /// Restores a saved conversation into the live session (from "Recent").
  void loadConversation(TutorConversation conversation) {
    final messages = conversation.messages;
    _seq = messages.isEmpty
        ? 0
        : messages.map((m) => m.id).reduce((a, b) => a > b ? a : b) + 1;
    _thread++;
    state = TutorSession(messages: messages);
  }

  /// Clears the thread and re-greets — the chat's "new conversation" action.
  ///
  /// A new conversation is a clean slate: the mode and everything Numi had
  /// learned about the student go with it.
  void reset() {
    _seq = 0;
    _thread++;
    state = TutorSession(
      messages: [_assistantFrom(_service.greeting(null))],
    );
  }

  /// [id] reuses the bubble a streamed reply was already growing in, so the
  /// finished turn lands where the student is reading instead of below it.
  TutorMessage _assistantFrom(TutorResponse response, {int? id}) => TutorMessage(
        id: id ?? _nextId(),
        role: TutorRole.assistant,
        text: response.text,
        card: response.card,
        focus: response.focus,
        // The structured explanation, when the mode renders one. Already
        // gated server-side: every equation on it matched a verified line or
        // is a closed identity, and the answer card is the app's own string.
        lesson: response.lesson,
        suggestions: response.suggestions,
        // Where this turn points on the student's page. Already gated
        // server-side against the anchors the app itself derived.
        actions: response.actions,
      );
}

/// A reply being streamed into the thread (spec Part 18): the accumulated text
/// and the bubble it is going into, once there is one.
///
/// [thread] pins it to the conversation it was asked in — see
/// `TutorChatController._thread`.
class _LiveReply {
  _LiveReply(this.thread);

  final int thread;
  final StringBuffer _buffer = StringBuffer();

  /// The bubble showing this reply, or null until the first delta creates it.
  int? id;

  String get text => _buffer.toString();

  void write(String delta) => _buffer.write(delta);
}

/// Builders for the Tutor home's mock content. Isolated here so the UI reads a
/// single [TutorHomeData] object and a later data source can replace this whole
/// class without any widget change.
class TutorHomeContent {
  const TutorHomeContent._();

  static TutorHomeData build() => const TutorHomeData(
        suggestedPrompts: _suggestedPrompts,
        recentConversations: _recentConversations,
        categories: _categories,
        quickActions: _quickActions,
      );

  static const List<TutorPrompt> _suggestedPrompts = [
    // Every `color` here is painted as an icon on a 14% plate of itself, i.e. a
    // foreground — so the emerald entries are [AppColors.primaryDark] (the
    // documented emerald-on-light-surfaces tone), never the 2.97:1 identity one.
    TutorPrompt(
      label: 'Explain Algebra',
      icon: Icons.functions_rounded,
      color: AppColors.primaryDark,
      message: 'Can you explain algebra to me?',
    ),
    TutorPrompt(
      label: 'Help Me With Fractions',
      icon: Icons.pie_chart_outline_rounded,
      color: AppColors.secondary,
      message: 'I need help with fractions.',
    ),
    TutorPrompt(
      label: 'Teach Geometry',
      icon: Icons.change_history_rounded,
      color: AppColors.accentAmber,
      message: 'Teach me some geometry.',
    ),
    TutorPrompt(
      label: 'Prepare For Exams',
      icon: Icons.assignment_turned_in_rounded,
      color: AppColors.accentCoral,
      message: 'Help me prepare for my exams.',
    ),
    TutorPrompt(
      label: 'Create A Quiz',
      icon: Icons.quiz_outlined,
      color: AppColors.secondary,
      message: 'Create a quiz for me.',
    ),
  ];

  static const List<TutorCategory> _categories = [
    TutorCategory(
      label: 'Algebra',
      icon: Icons.functions_rounded,
      color: AppColors.primaryDark,
      message: 'Can you explain algebra to me?',
    ),
    TutorCategory(
      label: 'Geometry',
      icon: Icons.change_history_rounded,
      color: AppColors.accentAmber,
      message: 'Teach me some geometry.',
    ),
    TutorCategory(
      label: 'Fractions',
      icon: Icons.pie_chart_outline_rounded,
      color: AppColors.secondary,
      message: 'Help me understand fractions.',
    ),
    TutorCategory(
      label: 'Calculus',
      icon: Icons.show_chart_rounded,
      color: AppColors.secondaryLight,
      message: 'Can you introduce me to calculus?',
    ),
    TutorCategory(
      label: 'Trigonometry',
      icon: Icons.architecture_rounded,
      color: AppColors.accentCoral,
      message: 'Explain trigonometry to me.',
    ),
    TutorCategory(
      label: 'Word Problems',
      icon: Icons.menu_book_rounded,
      color: AppColors.accentCoral,
      message: 'Help me with word problems.',
    ),
    // Statistics moves off the emerald ramp: Algebra now holds primaryDark, and
    // two categories must not share a tile colour. Info-blue is the categorical
    // hue that reads as "data" and clears AA on white (5.59:1).
    TutorCategory(
      label: 'Statistics',
      icon: Icons.bar_chart_rounded,
      color: AppColors.info,
      message: 'Can you teach me statistics?',
    ),
  ];

  static const List<TutorQuickAction> _quickActions = [
    TutorQuickAction(
      label: 'Ask Numi',
      icon: Icons.forum_rounded,
      color: AppColors.primaryDark,
      kind: TutorQuickActionKind.askMatheasy,
    ),
    TutorQuickAction(
      label: 'Upload Question',
      icon: Icons.upload_file_rounded,
      color: AppColors.secondary,
      kind: TutorQuickActionKind.uploadQuestion,
    ),
    TutorQuickAction(
      label: 'Practice Topic',
      icon: Icons.fitness_center_rounded,
      color: AppColors.accentAmber,
      kind: TutorQuickActionKind.practiceTopic,
    ),
    TutorQuickAction(
      label: 'Create Quiz',
      icon: Icons.quiz_outlined,
      color: AppColors.accentCoral,
      kind: TutorQuickActionKind.createQuiz,
    ),
  ];

  static const List<TutorConversation> _recentConversations = [
    TutorConversation(
      id: 'c1',
      title: 'Solving Linear Equations',
      preview: 'We subtract 5 because we want x by itself…',
      icon: Icons.calculate_rounded,
      messages: [
        TutorMessage.user(id: 0, text: 'How do I solve 2x + 5 = 13?'),
        TutorMessage(
          id: 1,
          role: TutorRole.assistant,
          text: "Let's isolate x! First subtract 5 from both sides to get "
              '2x = 8, then divide by 2 to find x = 4. 🎉',
          suggestions: [
            SuggestionAction.tellMeWhy,
            SuggestionAction.giveExample,
          ],
        ),
      ],
    ),
    TutorConversation(
      id: 'c2',
      title: 'Understanding Fractions',
      preview: 'Same bottom number first, then add the tops…',
      icon: Icons.pie_chart_outline_rounded,
      messages: [
        TutorMessage.user(id: 0, text: 'How do I add 3/4 + 1/2?'),
        TutorMessage(
          id: 1,
          role: TutorRole.assistant,
          text: 'Make the denominators match! 1/2 is the same as 2/4, so '
              '3/4 + 2/4 = 5/4. Keep the bottom, add the tops. 👍',
          suggestions: [SuggestionAction.explainSimpler],
        ),
      ],
    ),
    TutorConversation(
      id: 'c3',
      title: 'Quadratic Formula Basics',
      preview: 'Plug a, b and c into the formula…',
      icon: Icons.show_chart_rounded,
      messages: [
        TutorMessage.user(id: 0, text: 'What is the quadratic formula?'),
        TutorMessage(
          id: 1,
          role: TutorRole.assistant,
          text: 'The quadratic formula finds x for any ax² + bx + c = 0: '
              'x = (−b ± √(b² − 4ac)) / 2a. It always works, even when '
              'factoring is tricky!',
          suggestions: [
            SuggestionAction.giveExample,
            SuggestionAction.createQuiz,
          ],
        ),
      ],
    ),
  ];
}
