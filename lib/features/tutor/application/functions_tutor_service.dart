import 'dart:convert';

import '../../../core/theme/math_semantics.dart';
import '../../result/domain/result_models.dart';
import '../../result/domain/visual_models.dart';
import '../domain/tutor_models.dart';
import 'tutor_reply_engine.dart';
import 'tutor_service.dart';

/// Real Numi — calls the `tutorReply` Cloud Function (OpenAI server-side) for
/// each message, handing it the mode, the full verified solve context and what
/// it has learned about the student. The opening [greeting] stays local (it's
/// synchronous and needs no model), reusing the offline [TutorReplyEngine].
///
/// Used only for signed-in users with Firebase configured; the unconfigured
/// checkout keeps [MockTutorService] (see [tutorServiceProvider]).
/// Invokes a streaming callable, reporting each partial chunk to `onChunk` and
/// resolving with the final result — the shape `streamFunction` provides.
typedef TutorStreamCall = Future<Map<String, dynamic>> Function(
  String name,
  Map<String, dynamic> data,
  void Function(Map<String, dynamic> chunk) onChunk,
);

class FunctionsTutorService implements TutorService {
  const FunctionsTutorService(
    this._call, {
    this.engine = const TutorReplyEngine(),
    TutorStreamCall? stream,
  }) : _stream = stream;

  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)
      _call;

  /// The streaming transport, when one is available. Optional so a caller that
  /// only has the plain callable — and every existing test — still constructs.
  final TutorStreamCall? _stream;
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
    List<String> studentWork = const [],
    void Function(String delta)? onDelta,
  }) async {
    final request = <String, dynamic>{
      'userText': userText,
      'mode': mode.id,
      'helpLevel': memory.helpLevel,
      'history': [
        for (final m in history)
          if (m.role != TutorRole.system)
            {
              'role': m.role == TutorRole.user ? 'user' : 'assistant',
              // A photo-only turn carries no text; send a marker rather than an
              // empty string so the transcript still reads as a turn.
              // `transcriptText` folds an assistant turn's lesson cards back
              // into its words — otherwise the history would show only the
              // short spoken line and hide everything already taught.
              'text': m.text.isEmpty && m.hasImage ? '[photo]' : m.transcriptText,
            },
      ],
      if (context != null)
        ...TutorRequestMapper.context(
          context,
          // The photo is uploaded once per conversation, on the student's first
          // message. The server independently drops it on later turns, but the
          // saving that matters is here: not putting a photo on the wire from a
          // phone dozens of times a session. "First" is measured by the
          // student's turns — Numi's greeting is already in `history`.
          includeImage: history.every((m) => m.role != TutorRole.user),
        ),
      if (!memory.isEmpty) 'memory': TutorRequestMapper.memory(memory),
      // Checked server-side against the verified solution before the model sees
      // it — see `tutorWork.ts`. The model is handed a verdict, not a judgement
      // call.
      if (studentWork.isNotEmpty) 'studentWork': studentWork,
    };

    final stream = _stream;
    // Streaming costs an extra round-trip shape to set up, so it is only used
    // when someone is actually watching the words arrive.
    final json = onDelta == null || stream == null
        ? await _call('tutorReply', request)
        : await stream('tutorReply', request, (chunk) {
            final delta = chunk['delta'];
            // Each chunk is the NEXT piece, never the whole reply so far —
            // matching what `ReplyStreamer` emits server-side.
            if (delta is String && delta.isNotEmpty) onDelta(delta);
          });
    return TutorReplyMapper.toResponse(json);
  }
}

/// Pure [TutorLaunchContext] → request-JSON mapping.
///
/// Split out from the service so the wire shape is unit-testable without a
/// Firebase stub — this is the half of the contract that was previously dropping
/// everything but the problem LaTeX on the floor.
class TutorRequestMapper {
  const TutorRequestMapper._();

  /// [includeImage] gates the scan photo only. Pass false on every turn after
  /// the student's first message: the pixels are already read and quoted in the
  /// transcript, so re-uploading them costs bandwidth and vision tokens for
  /// nothing. Everything else in the context is cheap text and always sent.
  static Map<String, dynamic> context(
    TutorLaunchContext context, {
    bool includeImage = true,
  }) {
    final out = <String, dynamic>{};
    final problem = context.problem;
    if (problem != null) {
      out['problem'] = {
        'questionLatex': problem.questionLatex,
        if (problem.questionText != null) 'questionText': problem.questionText,
        if (problem.problemType != null) 'problemType': problem.problemType,
        if (problem.topic != null) 'topic': problem.topic,
        if (problem.difficulty != null) 'difficulty': problem.difficulty,
        if (problem.finalAnswer != null) 'finalAnswer': problem.finalAnswer,
        'verified': problem.verified,
        if (problem.verifyText != null) 'verifyText': problem.verifyText,
        if (problem.steps.isNotEmpty)
          'steps': [
            for (final step in problem.steps)
              {
                'title': step.title,
                'resultLatex': step.resultLatex,
                if (step.detail.isNotEmpty) 'detail': step.detail,
                if (step.rule != null) 'rule': step.rule,
              },
          ],
        if (problem.commonMistakes.isNotEmpty)
          'commonMistakes': problem.commonMistakes,
        if (problem.source != null) 'source': problem.source,
        // HOW the problem was read, so a dispute about the question can be
        // answered honestly instead of defended.
        if (problem.ocrLatex != null ||
            problem.ocrConfidence != null ||
            problem.ocrUncertain.isNotEmpty)
          'ocr': {
            if (problem.ocrLatex != null) 'latex': problem.ocrLatex,
            if (problem.ocrConfidence != null)
              'confidence': problem.ocrConfidence,
            if (problem.ocrUncertain.isNotEmpty)
              'uncertain': problem.ocrUncertain,
          },
        if (problem.practice.isNotEmpty) 'practice': problem.practice,
        // The map of the page. Sent on EVERY turn, unlike the photo: it is a
        // few hundred bytes of text, and it is what lets Numi keep pointing at
        // the student's own handwriting long after the pixels stopped being
        // uploaded.
        if (problem.anchors.isNotEmpty)
          'anchors': [for (final a in problem.anchors) a.toJson()],
      };
      // The photo itself rides at the TOP level, not inside `problem`: the
      // server reads it once, on the opening turn, and drops it thereafter.
      final bytes = includeImage ? problem.scanImageBytes : null;
      if (bytes != null && bytes.isNotEmpty) {
        out['imageBase64'] = base64Encode(bytes);
        out['mimeType'] = 'image/jpeg';
      }
    } else if (context.questionLatex != null) {
      // A caller with only the scalars still gets a well-formed problem block.
      out['problem'] = {
        'questionLatex': context.questionLatex,
        if (context.equationType != null) 'problemType': context.equationType,
        if (context.topicLabel != null) 'topic': context.topicLabel,
        if (context.answerLatex != null) 'finalAnswer': context.answerLatex,
        'verified': context.answerLatex != null,
      };
    }

    final focus = context.stepFocus;
    if (focus != null) {
      out['stepFocus'] = {
        'summary': focus.summary,
        if (focus.index != null) 'index': focus.index,
        if (focus.total != null) 'total': focus.total,
        if (focus.equationLatex != null) 'equationLatex': focus.equationLatex,
      };
    } else if (context.visualStepSummary != null) {
      out['stepFocus'] = {'summary': context.visualStepSummary};
    }
    return out;
  }

  static Map<String, dynamic> memory(TutorMemory memory) => {
        if (memory.conceptsCovered.isNotEmpty)
          'conceptsCovered': memory.conceptsCovered,
        if (memory.mistakes.isNotEmpty) 'mistakes': memory.mistakes,
        if (memory.strengths.isNotEmpty) 'strengths': memory.strengths,
        if (memory.style != null) 'style': memory.style!.name,
      };
}

/// Pure JSON → [TutorResponse] mapping for the `tutorReply` response.
class TutorReplyMapper {
  const TutorReplyMapper._();

  static TutorResponse toResponse(Map<String, dynamic> json) {
    final text = json['reply'] is String ? json['reply'] as String : '';
    return TutorResponse(
      text: text.isEmpty ? "Let's keep going!" : text,
      card: _card(json['card']),
      focus: _focus(json['focus']),
      lesson: lesson(json['lesson']),
      suggestions: _suggestions(json['suggestions']),
      meta: _meta(json['meta']),
      actions: actions(json['actions']),
      certainty: TutorCertainty.parse(
        json['verification'] is String ? json['verification'] as String : null,
      ),
    );
  }

  /// The structured teaching, as cards.
  ///
  /// Every equation here has already passed the server's golden-rule gate
  /// (`tutorLesson.ts`): it is the app's own copy of verified maths, or a closed
  /// arithmetic fact re-checked with mathjs, or it was dropped before it left
  /// the server. The final answer is the app's verified string, substituted
  /// there — the model's own answer never travels. So this only shapes what
  /// arrived, and it drops rather than repairs: a lesson with no goal, or one
  /// with nothing but a goal, renders as no cards and the prose stands alone.
  static TutorLesson? lesson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final goal = _nullable(map['goal']);
    if (goal == null) return null;

    final steps = <TutorLessonStep>[];
    final rawSteps = map['steps'];
    if (rawSteps is List) {
      for (final item in rawSteps) {
        if (item is! Map) continue;
        final step = item.cast<String, dynamic>();
        final title = _nullable(step['title']);
        final explanation = _string(step['explanation']).trim();
        if (title == null && explanation.isEmpty) continue;
        steps.add(
          TutorLessonStep(
            title: title ?? explanation,
            explanation: explanation,
            equation: _nullable(step['equation']),
          ),
        );
      }
    }

    final lesson = TutorLesson(
      goal: goal,
      steps: steps,
      concept: _nullable(map['concept']),
      commonMistake: _nullable(map['commonMistake']),
      finalAnswer: _nullable(map['finalAnswer']),
    );
    return lesson.hasContent ? lesson : null;
  }

  /// The gestures at the scanned page.
  ///
  /// Every one has already survived the server's gate (`tutorActions.ts`): the
  /// target is the id of an anchor the APP derived, never a coordinate the
  /// model proposed. What's left to do here is only shaping — plus dropping a
  /// gesture type this build doesn't know how to draw, which is the honest
  /// response to a newer server.
  static List<TutorAction> actions(Object? raw) {
    if (raw is! List) return const [];
    final out = <TutorAction>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final type = TutorActionType.parse(
        map['type'] is String ? map['type'] as String : null,
      );
      final target = _nullable(map['target']);
      if (type == null || target == null) continue;
      final action = TutorAction(
        type: type,
        target: target,
        role: MathRole.parse(map['role'] is String ? map['role'] as String : null),
      );
      if (!out.contains(action)) out.add(action);
    }
    return out;
  }

  /// The server sends chip IDS; unknown ids are dropped rather than guessed at.
  ///
  /// Free-text entries are still keyword-matched so a response from an older
  /// deployed function (which returned prose prompts) keeps working.
  static List<SuggestionAction> _suggestions(Object? raw) {
    final actions = <SuggestionAction>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is! String) continue;
        final action = SuggestionAction.fromId(item) ?? _matchAction(item);
        if (action != null && !actions.contains(action)) actions.add(action);
      }
    }
    return actions.isEmpty ? _defaults : actions.take(3).toList();
  }

  /// The card has already been machine-verified server-side (`tutorCard.ts`) —
  /// an unverifiable one never reaches here. This only shapes it for the UI.
  static TutorCard? _card(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    return switch (map['kind']) {
      'quiz' => _quiz(map),
      'practice' => _practice(map),
      _ => null,
    };
  }

  static TutorCard? _quiz(Map<String, dynamic> map) {
    final options = map['options'];
    final correctIndex = map['correctIndex'];
    if (options is! List || correctIndex is! int) return null;
    if (correctIndex < 0 || correctIndex >= options.length) return null;
    final texts = [
      for (final o in options)
        if (o is String) o,
    ];
    if (texts.length != options.length || texts.length < 2) return null;
    return QuizCard(
      QuizQuestion(
        prompt: _string(map['prompt']),
        promptLatex: _nullable(map['promptLatex']),
        options: [
          for (var i = 0; i < texts.length; i++)
            QuizOption(text: texts[i], isCorrect: i == correctIndex),
        ],
        explanation: _string(map['explanation']),
      ),
    );
  }

  static TutorCard? _practice(Map<String, dynamic> map) {
    final latex = _nullable(map['questionLatex']);
    if (latex == null) return null;
    final xp = map['xpReward'];
    return PracticeCard(
      PracticePrompt(
        questionLatex: latex,
        difficulty: switch (map['difficulty']) {
          'easy' => Difficulty.easy,
          'hard' => Difficulty.hard,
          _ => Difficulty.medium,
        },
        xpReward: xp is int ? xp : 30,
        encouragement: _string(map['encouragement']),
      ),
    );
  }

  /// The focus equation has already been checked against the app's verified
  /// maths server-side (`tutorFocus.ts`) — the model's own LaTeX never reaches
  /// here. This only shapes it for the UI.
  ///
  /// A span that isn't a substring of the equation is dropped rather than
  /// searched for loosely: it would tint the wrong symbol, and pointing at the
  /// wrong thing while explaining is worse than pointing at nothing.
  static TutorFocus? _focus(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final latex = _nullable(map['latex']);
    final caption = _string(map['caption']);
    if (latex == null || caption.isEmpty) return null;

    final spans = map['spans'];
    final highlights = <MathHighlight>[];
    if (spans is List) {
      for (final span in spans) {
        if (span is! Map) continue;
        final text = _nullable(span['text']);
        if (text == null || !latex.contains(text)) continue;
        highlights.add(
          MathHighlight(text: text, role: MathRole.parse(_nullable(span['role']))),
        );
      }
    }
    if (highlights.isEmpty) return null;
    return TutorFocus(
      latex: latex,
      caption: caption,
      highlights: highlights,
      sketch: _sketch(map['sketch'], caption),
    );
  }

  /// The optional drawing (spec Part 9), as a [VisualConcept] the shared
  /// concept painter already knows how to draw.
  ///
  /// The server sends a kind and numbers only — no strings — because every
  /// coordinate is derived there from the verified equation. An unknown kind
  /// means a newer server than this build: drop the drawing rather than guess
  /// at it.
  static VisualConcept? _sketch(Object? raw, String caption) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final kind = _sketchKinds[_string(map['kind'])];
    if (kind == null) return null;

    final params = <String, double>{};
    final rawParams = map['params'];
    if (rawParams is Map) {
      for (final entry in rawParams.entries) {
        final value = entry.value;
        if (value is num && value.isFinite) {
          params[entry.key.toString()] = value.toDouble();
        }
      }
    }
    if (params.isEmpty) return null;
    return VisualConcept(
      kind: kind,
      caption: caption,
      // The unit circle paints its angle on the canvas when labelled, and
      // "30°" reads the same in every language the tutor speaks.
      labels: kind == VisualConceptKind.unitCircle
          ? {'angle': '${_trim(params['angleDegrees'] ?? 0)}°'}
          : const {},
      params: params,
    );
  }

  static const _sketchKinds = <String, VisualConceptKind>{
    'fraction': VisualConceptKind.fractionBar,
    'numberLine': VisualConceptKind.numberLine,
    'line': VisualConceptKind.linearGraph,
    'parabola': VisualConceptKind.parabolaGraph,
    'area': VisualConceptKind.areaUnderCurve,
    'unitCircle': VisualConceptKind.unitCircle,
  };

  /// `30.0` → `30`, so an angle label reads like a protractor.
  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  static TutorTurnMeta _meta(Object? raw) {
    if (raw is! Map) return const TutorTurnMeta();
    final map = raw.cast<String, dynamic>();
    final concepts = map['conceptsCovered'];
    return TutorTurnMeta(
      conceptsCovered: concepts is List
          ? [
              for (final c in concepts)
                if (c is String && c.trim().isNotEmpty) c.trim(),
            ]
          : const [],
      mistake: _nullable(map['mistake']),
      understanding: switch (map['understanding']) {
        'struggling' => TutorUnderstanding.struggling,
        'confident' => TutorUnderstanding.confident,
        _ => TutorUnderstanding.following,
      },
      checkpoint: map['checkpoint'] == true,
      style: switch (map['style']) {
        'concise' => TutorStyle.concise,
        'detailed' => TutorStyle.detailed,
        'visual' => TutorStyle.visual,
        _ => null,
      },
    );
  }

  static String _string(Object? value) => value is String ? value : '';

  static String? _nullable(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static const List<SuggestionAction> _defaults = [
    SuggestionAction.tellMeWhy,
    SuggestionAction.giveExample,
    SuggestionAction.explainSimpler,
  ];

  /// Best-effort keyword match, kept only for responses from an older deployed
  /// `tutorReply` that returned free-text suggestion prompts.
  static SuggestionAction? _matchAction(String text) {
    final t = text.toLowerCase();
    if (t.contains('simpl')) return SuggestionAction.explainSimpler;
    if (t.contains('example')) return SuggestionAction.giveExample;
    if (t.contains('why')) return SuggestionAction.tellMeWhy;
    if (t.contains('method') || t.contains('another way')) {
      return SuggestionAction.showAnotherMethod;
    }
    if (t.contains('quiz')) return SuggestionAction.createQuiz;
    if (t.contains('practice') || t.contains('practise')) {
      return SuggestionAction.practiceMore;
    }
    return null;
  }
}
