// Tests for the real-AI backend integration: the JSON → domain mappers for the
// solve/tutor/scan Cloud Functions, and the FunctionsScannerService flow with a
// fake callable. The mapping is pure, so it's tested without the cloud_functions
// plugin (the services take an injected call function).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/core/theme/math_semantics.dart';
import 'package:matheasy/features/result/application/functions_solver_service.dart';
import 'package:matheasy/features/result/domain/animation_schema.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart';
import 'package:matheasy/features/scan/application/functions_scanner_service.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/tutor/application/functions_tutor_service.dart';
import 'package:matheasy/features/tutor/domain/tutor_context_builder.dart';
import 'package:matheasy/features/tutor/domain/tutor_models.dart';

const _equation = DetectedEquation(
  latex: '2x + 5 = 13',
  confidence: 0.98,
  source: ScanSource.camera,
  kind: EquationKind.linear,
);

void main() {
  group('SolveResponseMapper (§4 schema)', () {
    test('maps a verified solveEquation payload onto ResultData', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemLatex': '5x^2 + 3x - 2 = 0',
        'problemType': 'quadratic_equation',
        'finalAnswer': {
          'latex': r'x_1 = -1,\; x_2 = \tfrac{2}{5}',
          'plain': 'x = -1 or x = 2/5',
        },
        'verified': true,
        'methods': [
          {
            'id': 'factoring',
            'name': 'Factoring',
            'examPick': true,
            'steps': [
              {
                'expression': '(5x - 2)(x + 1) = 0',
                'operation': 'Factor',
                'why': 'Split the middle term and factor by grouping.',
              },
              {
                'expression': r'x = -1,\ x = \tfrac{2}{5}',
                'operation': 'Find the roots',
                'why': 'Each factor can be zero.',
              },
            ],
          },
          {
            'id': 'quadratic_formula',
            'name': 'Quadratic formula',
            'examPick': false,
            'steps': [
              {'expression': 'a=5, b=3, c=-2', 'operation': 'Identify a, b, c', 'why': ''},
            ],
          },
        ],
        'graph': {
          'kind': 'function',
          'expression': '5x^2 + 3x - 2',
          'keyPoints': [
            {'label': 'root', 'x': -1, 'y': 0},
            {'label': 'root', 'x': 0.4, 'y': 0},
            {'label': 'vertex', 'x': -0.3, 'y': -2.45},
          ],
          'curve': [
            {'x': -2, 'y': 12},
            {'x': -1, 'y': 0},
            {'x': 0, 'y': -2},
            {'x': 1, 'y': 6},
          ],
        },
      });

      expect(result.equation, _equation);
      expect(result.type, ResultType.quadratic);
      expect(result.verified, isTrue);
      expect(result.answerLatex, r'x_1 = -1,\; x_2 = \tfrac{2}{5}');
      expect(result.answerPlain, 'x = -1 or x = 2/5');
      // Steps come from the exam-pick method.
      expect(result.steps, hasLength(2));
      expect(result.steps.first.operationLabel, 'Factor');
      expect(result.steps.first.resultLatex, '(5x - 2)(x + 1) = 0');
      // Both methods carried; recommended flag mirrors examPick.
      expect(result.methods, hasLength(2));
      expect(result.methods.first.recommended, isTrue);
      expect(result.methods[1].recommended, isFalse);
      // §4 doesn't carry explanations / practice → empty (tabs show empty state).
      expect(result.explanations, isEmpty);
      expect(result.practice, isEmpty);
      // Graph mapped with typed key points.
      expect(result.graph, isNotNull);
      expect(result.graph!.expression, '5x^2 + 3x - 2');
      expect(result.graph!.keyPoints, hasLength(3));
      expect(result.graph!.keyPoints.last.label, 'vertex');
      expect(result.graph!.keyPoints.last.y, closeTo(-2.45, 0.001));
      // §7 curve samples parsed into plottable points.
      expect(result.graph!.curve, hasLength(4));
      expect(result.graph!.curve[1], const Offset(-1, 0));
      // A payload WITHOUT the animation sidecar → null (the common case). The
      // result UI renders exactly as today when this is absent.
      expect(result.animationSchema, isNull);
    });

    test('couldn\'t-verify → no answer, honest state', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemLatex': 'x^2 + 1 = 0',
        'problemType': 'quadratic_equation',
        'finalAnswer': null,
        'verified': false,
        'methods': <dynamic>[],
        'graph': null,
      });
      expect(result.verified, isFalse);
      expect(result.answerLatex, isEmpty);
      expect(result.steps, isEmpty);
      expect(result.methods, isEmpty);
      expect(result.graph, isNull);
      expect(result.verifyText, contains("couldn't verify"));
      // No sidecar on a couldn't-verify payload either.
      expect(result.animationSchema, isNull);
    });

    test('parses the optional animationSchema when the server attaches it', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemLatex': '2x + 5 = 13',
        'problemType': 'linear_equation',
        'finalAnswer': {'latex': 'x = 4', 'plain': 'x = 4'},
        'verified': true,
        'methods': <dynamic>[],
        'animationSchema': [
          {
            'stepIndex': 0,
            'changeType': 'SUBTRACT_FROM_BOTH_SIDES',
            'beforeLatex': '2x + 5 = 13',
            'afterLatex': '2x = 8',
            'animationTemplate': 'move_across_equals',
            'tokens': [
              {
                'value': '5',
                'fromPath': 'L/1',
                'toPath': 'R/1',
                'color': 'pink',
                'highlight': 'circle',
              },
            ],
            'explanationKey': 'anim.step.SUBTRACT_FROM_BOTH_SIDES',
          },
          {
            'stepIndex': 1,
            'changeType': 'DIVIDE_FROM_BOTH_SIDES',
            'beforeLatex': '2x = 8',
            'afterLatex': 'x = 4',
            'animationTemplate': 'divide_both_sides',
            'tokens': [
              {
                'value': '2',
                'fromPath': 'L/0',
                'toPath': 'L/1',
                'color': 'blue',
                'highlight': 'box',
              },
              // A new token (no old origin) — fromPath is explicitly null.
              {
                'value': '2',
                'fromPath': null,
                'toPath': 'R/1',
                'color': 'blue',
                'highlight': 'box',
              },
            ],
            'explanationKey': 'anim.step.DIVIDE_FROM_BOTH_SIDES',
          },
        ],
      });

      final schema = result.animationSchema;
      expect(schema, isNotNull);
      expect(schema!.length, 2);

      final first = schema[0];
      expect(first.stepIndex, 0);
      expect(first.changeType, 'SUBTRACT_FROM_BOTH_SIDES');
      expect(first.beforeLatex, '2x + 5 = 13');
      expect(first.afterLatex, '2x = 8');
      expect(first.template, AnimationTemplate.moveAcrossEquals);
      expect(first.explanationKey, 'anim.step.SUBTRACT_FROM_BOTH_SIDES');
      expect(first.tokens, hasLength(1));
      expect(first.tokens.single.value, '5');
      expect(first.tokens.single.fromPath, 'L/1');
      expect(first.tokens.single.toPath, 'R/1');
      expect(first.tokens.single.color, TokenColor.pink);
      expect(first.tokens.single.highlight, TokenHighlight.circle);

      final second = schema[1];
      expect(second.template, AnimationTemplate.divideBothSides);
      expect(second.tokens, hasLength(2));
      // The explicit-null endpoint survives the round trip.
      expect(second.tokens[1].fromPath, isNull);
      expect(second.tokens[1].toPath, 'R/1');
    });

    test('an empty animationSchema array parses to null (no entry point shown)', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemLatex': '2x + 5 = 13',
        'problemType': 'linear_equation',
        'finalAnswer': {'latex': 'x = 4', 'plain': 'x = 4'},
        'verified': true,
        'methods': <dynamic>[],
        'animationSchema': <dynamic>[],
      });
      expect(result.animationSchema, isNull);
    });

    test('unknown enum values degrade to safe fallbacks (never throw)', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemLatex': '2x + 5 = 13',
        'problemType': 'linear_equation',
        'finalAnswer': {'latex': 'x = 4', 'plain': 'x = 4'},
        'verified': true,
        'methods': <dynamic>[],
        'animationSchema': [
          {
            'stepIndex': 0,
            'changeType': 'FUTURE_CHANGE_TYPE',
            'beforeLatex': '2x + 5 = 13',
            'afterLatex': '2x = 8',
            // A template/colour/highlight a newer server might send.
            'animationTemplate': 'warp_speed',
            'tokens': [
              {
                'value': '5',
                'fromPath': 'L/1',
                'toPath': 'R/1',
                'color': 'chartreuse',
                'highlight': 'sparkle',
              },
            ],
            'explanationKey': 'anim.step.FUTURE_CHANGE_TYPE',
          },
        ],
      });
      final step = result.animationSchema!.steps.single;
      // Unknown template → the server's own default; unknown token enums → the
      // model defaults. An older client can't crash on a newer server.
      expect(step.template, AnimationTemplate.fadeInNewLine);
      expect(step.tokens.single.color, TokenColor.blue);
      expect(step.tokens.single.highlight, TokenHighlight.box);
    });

    test('routeToTutor → conceptual state, no answer, honest framing', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemLatex': r'\text{Prove that } \sqrt{2} \text{ is irrational}',
        'problemType': 'conceptual',
        'finalAnswer': null,
        'verified': false,
        'routeToTutor': true,
        'methods': <dynamic>[],
        'graph': null,
      });
      expect(result.routeToTutor, isTrue);
      expect(result.verified, isFalse);
      expect(result.answerLatex, isEmpty);
      // Honest, proof-aware framing — NOT the generic "couldn't verify" error.
      expect(result.verifyText, contains('proof'));
      expect(result.verifyText, isNot(contains("couldn't verify")));
      // A round-trip (history caching) preserves the flag.
      final restored = ResultData.fromJson(result.toJson());
      expect(restored.routeToTutor, isTrue);
    });

    test('an ordinary verified payload leaves routeToTutor false', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemType': 'linear_equation',
        'verified': true,
        'finalAnswer': {'latex': 'x = 4', 'plain': 'x = 4'},
      });
      expect(result.routeToTutor, isFalse);
    });

    test('degrades gracefully on missing / unknown fields', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'problemType': 'nonsense',
        'verified': true,
        'finalAnswer': {'latex': 'x = 1', 'plain': 'x = 1'},
      });
      expect(result.type, ResultType.expression); // unknown → fallback
      expect(result.difficulty, Difficulty.medium);
      expect(result.steps, isEmpty);
      expect(result.methods, isEmpty);
      expect(result.tutorIntro, isNotEmpty); // fallback text
    });

    test('falls back to the fraction caption for arithmetic on a fraction scan', () {
      const fractionEq = DetectedEquation(
        latex: r'\frac{3}{4} + \frac{1}{2}',
        confidence: 0.9,
        source: ScanSource.camera,
        kind: EquationKind.fraction,
      );
      final result = SolveResponseMapper.toResultData(fractionEq, {
        'problemType': 'arithmetic',
        'verified': true,
        'finalAnswer': {'latex': r'\tfrac{5}{4}', 'plain': '5/4'},
        'methods': <dynamic>[],
      });
      expect(result.type, ResultType.fraction);
    });

    test('a geometry-kind scan maps to ResultType.geometry, kind BEFORE the '
        'problemType switch (order is load-bearing)', () {
      // The solver is geometry-blind: it parses "third angle = 180 − 86 − 37" as
      // a linear equation. The Vision topic on `kind` is the only geometry
      // signal, and _typeFor must honour it BEFORE the problemType switch —
      // otherwise the linear_equation arm would grab it and mis-type it.
      const geoEq = DetectedEquation(
        latex: r'x = 180 - 86 - 37',
        confidence: 0.9,
        source: ScanSource.camera,
        kind: EquationKind.geometry,
      );
      final result = SolveResponseMapper.toResultData(geoEq, {
        'problemType': 'linear_equation', // would win if order were wrong
        'verified': true,
        'finalAnswer': {'latex': 'x = 57', 'plain': 'x = 57'},
        'methods': <dynamic>[],
      });
      expect(result.type, ResultType.geometry);
    });
  });

  group('TutorReplyMapper', () {
    test('maps reply + keyword-matches suggestions to typed chips', () {
      final response = TutorReplyMapper.toResponse({
        'reply': 'Great question! First, subtract 5.',
        'suggestions': [
          'Can you explain that more simply?',
          'Give me an example',
          'Show another method',
          'totally unrelated text',
        ],
      });
      expect(response.text, contains('subtract 5'));
      expect(
        response.suggestions,
        containsAll([
          SuggestionAction.explainSimpler,
          SuggestionAction.giveExample,
          SuggestionAction.showAnotherMethod,
        ]),
      );
    });

    test('falls back to default chips when none match, and to text default', () {
      final response = TutorReplyMapper.toResponse({
        'reply': '',
        'suggestions': ['random', 'noise'],
      });
      expect(response.text, isNotEmpty);
      expect(response.suggestions, isNotEmpty);
    });

    // Spec Parts 7–8. The equation has already been checked against the app's
    // verified maths server-side (`tutorFocus.ts`); the mapper's job is to make
    // sure nothing that survives can point at the WRONG symbol.
    group('focus', () {
      test('maps the equation, caption and highlight roles', () {
        final response = TutorReplyMapper.toResponse({
          'reply': 'Look at the middle term.',
          'focus': {
            'latex': 'x^2 + 8x + 4 = 0',
            'caption': 'the coefficient of x',
            'spans': [
              {'text': '8x', 'role': 'operation'},
              {'text': '4', 'role': 'known'},
            ],
          },
        });
        final focus = response.focus!;
        expect(focus.latex, 'x^2 + 8x + 4 = 0');
        expect(focus.caption, 'the coefficient of x');
        expect(focus.highlights, [
          const MathHighlight(text: '8x', role: MathRole.operation),
          const MathHighlight(text: '4', role: MathRole.known),
        ]);
        expect(focus.leadRole, MathRole.operation);
      });

      test('drops a span that is not in the equation', () {
        final response = TutorReplyMapper.toResponse({
          'reply': 'x',
          'focus': {
            'latex': '2x + 1 = 5',
            'caption': 'here',
            'spans': [
              {'text': '9y', 'role': 'known'},
              {'text': '2x', 'role': 'unknown'},
            ],
          },
        });
        expect(response.focus!.highlights, [
          const MathHighlight(text: '2x', role: MathRole.unknown),
        ]);
      });

      test('an unknown role becomes the one colour that cannot mislead', () {
        final response = TutorReplyMapper.toResponse({
          'reply': 'x',
          'focus': {
            'latex': '2x + 1 = 5',
            'caption': 'here',
            'spans': [
              {'text': '5', 'role': 'correct'},
            ],
          },
        });
        expect(response.focus!.highlights.single.role, MathRole.aside);
      });

      // An equation with nothing lit up is just the reply restated.
      test('drops a focus with nothing left to highlight', () {
        expect(
          TutorReplyMapper.toResponse({
            'reply': 'x',
            'focus': {
              'latex': '2x + 1 = 5',
              'caption': 'here',
              'spans': [
                {'text': 'z', 'role': 'known'},
              ],
            },
          }).focus,
          isNull,
        );
        expect(
          TutorReplyMapper.toResponse({
            'reply': 'x',
            'focus': {'latex': '2x + 1 = 5', 'caption': 'here'},
          }).focus,
          isNull,
        );
      });

      // Spec Part 9. The server derives every number from the verified
      // equation, so the client's job is only to name the right drawing.
      test('maps a sketch onto the concept the app already knows how to paint',
          () {
        final focus = TutorReplyMapper.toResponse({
          'reply': 'Three of the four parts.',
          'focus': {
            'latex': r'\frac{3}{4}',
            'caption': 'three quarters',
            'spans': [
              {'text': '3', 'role': 'known'},
            ],
            'sketch': {
              'kind': 'fraction',
              'params': {'numerator': 3, 'denominator': 4},
            },
          },
        }).focus!;
        expect(focus.sketch!.kind, VisualConceptKind.fractionBar);
        expect(focus.sketch!.params, {'numerator': 3.0, 'denominator': 4.0});
        // The caption legends both the equation and the drawing.
        expect(focus.sketch!.caption, 'three quarters');
      });

      test('labels the unit circle with its angle, which every language reads',
          () {
        final focus = TutorReplyMapper.toResponse({
          'reply': 'Thirty degrees.',
          'focus': {
            'latex': r'\sin(30^\circ)',
            'caption': 'the angle',
            'spans': [
              {'text': '30', 'role': 'known'},
            ],
            'sketch': {
              'kind': 'unitCircle',
              'params': {'angleDegrees': 30},
            },
          },
        }).focus!;
        expect(focus.sketch!.labels['angle'], '30°');
      });

      test('drops a drawing it cannot paint, keeping the equation', () {
        TutorFocus focusWith(Object? sketch) => TutorReplyMapper.toResponse({
              'reply': 'x',
              'focus': {
                'latex': '2x + 1 = 5',
                'caption': 'here',
                'spans': [
                  {'text': '2x', 'role': 'unknown'},
                ],
                'sketch': sketch,
              },
            }).focus!;

        // A kind from a newer server than this build.
        expect(focusWith({'kind': 'hyperbola', 'params': {'a': 1}}).sketch,
            isNull);
        expect(focusWith({'kind': 'line'}).sketch, isNull); // no numbers
        expect(
          focusWith({
            'kind': 'line',
            'params': {'slope': 'two'},
          }).sketch,
          isNull,
        );
        expect(focusWith('fraction').sketch, isNull);
        expect(focusWith(null).sketch, isNull);
        // …and the equation itself still renders in every one of those cases.
        expect(focusWith(null).latex, '2x + 1 = 5');
      });

      test('a reply without a focus is unaffected', () {
        expect(TutorReplyMapper.toResponse({'reply': 'hi'}).focus, isNull);
        expect(
          TutorReplyMapper.toResponse({'reply': 'hi', 'focus': 'x = 4'}).focus,
          isNull,
        );
      });
    });
  });

  group('FunctionsTutorService streaming (spec Part 18)', () {
    test('uses the plain callable when nobody is watching the words', () async {
      var plain = 0;
      var streamed = 0;
      final service = FunctionsTutorService(
        (name, data) async {
          plain++;
          return {'reply': 'Done.'};
        },
        stream: (name, data, onChunk) async {
          streamed++;
          return {'reply': 'Done.'};
        },
      );

      final response = await service.reply('hi', history: const []);
      expect(plain, 1);
      expect(streamed, 0, reason: 'no onDelta — nothing to stream to');
      expect(response.text, 'Done.');
    });

    test('streams chunks to onDelta and returns the final response', () async {
      final service = FunctionsTutorService(
        (name, data) async => fail('should have taken the streaming path'),
        stream: (name, data, onChunk) async {
          expect(name, 'tutorReply');
          expect(data['userText'], 'why?');
          onChunk({'delta': 'Sub'});
          onChunk({'delta': 'tract '});
          onChunk({'delta': '5.'});
          return {
            'reply': 'Subtract 5.',
            'suggestions': ['tellMeWhy'],
          };
        },
      );

      final pieces = <String>[];
      final response = await service.reply(
        'why?',
        history: const [],
        onDelta: pieces.add,
      );
      expect(pieces, ['Sub', 'tract ', '5.']);
      expect(response.text, 'Subtract 5.');
      expect(response.suggestions, [SuggestionAction.tellMeWhy]);
    });

    test('ignores chunks that carry no delta text', () async {
      final service = FunctionsTutorService(
        (name, data) async => fail('should have taken the streaming path'),
        stream: (name, data, onChunk) async {
          onChunk({'delta': ''});
          onChunk({'delta': 42});
          onChunk(<String, dynamic>{});
          onChunk({'delta': 'Real.'});
          return {'reply': 'Real.'};
        },
      );

      final pieces = <String>[];
      await service.reply('hi', history: const [], onDelta: pieces.add);
      expect(pieces, ['Real.']);
    });

    test('falls back to the plain callable with no streaming transport', () async {
      // An older construction site (and every existing test) passes only the
      // callable; asking for deltas must not break it.
      var called = 0;
      final service = FunctionsTutorService((name, data) async {
        called++;
        return {'reply': 'Fine.'};
      });

      var deltas = 0;
      final response = await service.reply(
        'hi',
        history: const [],
        onDelta: (_) => deltas++,
      );
      expect(called, 1);
      expect(deltas, 0);
      expect(response.text, 'Fine.');
    });
  });

  group('what Numi is handed about a scanned problem', () {
    final photo = Uint8List.fromList([1, 2, 3, 4]);
    final scanned = DetectedEquation(
      latex: '2x + 5 = 13',
      confidence: 0.98,
      source: ScanSource.camera,
      kind: EquationKind.linear,
      imageBytes: photo,
      ocr: const {
        'latex': '2x + 5 = 1З',
        'confidence': 0.62,
        'uncertain': ['the 3 in 13'],
      },
    );

    ResultData resultFrom(DetectedEquation equation) => ResultData(
          equation: equation,
          type: ResultType.linear,
          difficulty: Difficulty.easy,
          answerLatex: 'x = 4',
          steps: const [],
          verifyText: '2(4) + 5 = 13 ✓',
          explanations: const [],
          methods: const [],
          practice: const [
            PracticeQuestion(
              questionLatex: '3x + 1 = 7',
              difficulty: Difficulty.easy,
              xpReward: 20,
            ),
            PracticeQuestion(
              questionLatex: '5x - 2 = 13',
              difficulty: Difficulty.medium,
              xpReward: 30,
            ),
          ],
          tutorIntro: '',
        );

    test('the builder carries the read, the practice and the photo', () {
      final problem = TutorContextBuilder.fromResult(resultFrom(scanned));
      expect(problem.ocrLatex, '2x + 5 = 1З');
      expect(problem.ocrConfidence, closeTo(0.62, 1e-9));
      expect(problem.ocrUncertain, ['the 3 in 13']);
      expect(problem.practice, ['3x + 1 = 7 (easy)', '5x - 2 = 13 (medium)']);
      expect(problem.scanImageBytes, photo);
    });

    test('a typed problem carries none of it, and that is not an error', () {
      const typed = DetectedEquation(
        latex: '2x + 5 = 13',
        confidence: 1,
        source: ScanSource.manual,
        kind: EquationKind.linear,
      );
      final problem = TutorContextBuilder.fromResult(resultFrom(typed));
      expect(problem.ocrLatex, isNull);
      expect(problem.ocrConfidence, isNull);
      expect(problem.ocrUncertain, isEmpty);
      expect(problem.scanImageBytes, isNull);
    });

    test('the mapper puts the read inside problem and the photo at the top', () {
      final json = TutorRequestMapper.context(
        TutorLaunchContext(problem: TutorContextBuilder.fromResult(resultFrom(scanned))),
      );
      final problem = json['problem'] as Map<String, dynamic>;
      expect(problem['ocr'], {
        'latex': '2x + 5 = 1З',
        'confidence': closeTo(0.62, 1e-9),
        'uncertain': ['the 3 in 13'],
      });
      expect(problem['practice'], ['3x + 1 = 7 (easy)', '5x - 2 = 13 (medium)']);
      // Top level, not inside `problem` — the server reads it once per chat.
      expect(json['imageBase64'], 'AQIDBA==');
      expect(json['mimeType'], 'image/jpeg');
    });

    test('the photo goes up once, on the student\'s first message', () async {
      final sent = <Map<String, dynamic>>[];
      final service = FunctionsTutorService((name, data) async {
        sent.add(data);
        return {'reply': 'ok'};
      });
      final context = TutorLaunchContext(
        problem: TutorContextBuilder.fromResult(resultFrom(scanned)),
      );

      // Numi greets first, so the transcript is non-empty before the student
      // has said anything — the photo must still ride along here.
      await service.reply(
        'why?',
        history: const [
          TutorMessage(id: 1, role: TutorRole.assistant, text: 'Hi!'),
        ],
        context: context,
      );
      // …and must NOT ride along again once the conversation is under way.
      await service.reply(
        'and then?',
        history: const [
          TutorMessage(id: 1, role: TutorRole.assistant, text: 'Hi!'),
          TutorMessage(id: 2, role: TutorRole.user, text: 'why?'),
          TutorMessage(id: 3, role: TutorRole.assistant, text: 'Because…'),
        ],
        context: context,
      );

      expect(sent.first['imageBase64'], 'AQIDBA==');
      expect(sent.last.containsKey('imageBase64'), isFalse);
      // The cheap text context is still sent on every turn.
      expect((sent.last['problem'] as Map<String, dynamic>)['ocr'], isNotNull);
    });
  });

  group('FunctionsScannerService', () {
    test('manual entry wraps typed latex without calling the backend', () async {
      var called = false;
      final service = FunctionsScannerService((name, data) async {
        called = true;
        return {};
      });

      final eq = await service.recognize(ScanSource.manual,
          manualLatex: r'x^2 - 4 = 0');
      expect(called, isFalse);
      expect(eq.latex, r'x^2 - 4 = 0');
      expect(eq.source, ScanSource.manual);
      expect(eq.kind, EquationKind.quadratic); // inferred from ^2
    });

    test('recognizes a photo via the callable and maps confidence', () async {
      final service = FunctionsScannerService((name, data) async {
        expect(name, 'recognizeEquation');
        expect(data['imageBase64'], isNotEmpty);
        return {'latex': r'\frac{1}{2}', 'confidence': 0.87};
      });

      final eq = await service
          .recognize(ScanSource.camera, imageBytes: _bytes());
      expect(eq.latex, r'\frac{1}{2}');
      expect(eq.confidence, closeTo(0.87, 0.001));
      expect(eq.kind, EquationKind.fraction);
    });

    test('keeps the transcription pass\'s own account of the read', () async {
      final service = FunctionsScannerService((name, data) async => {
            'latex': '2x + 5 = 13',
            'confidence': 0.9,
            'ocr': {
              'latex': '2x + 5 = 1З',
              'confidence': 0.62,
              'uncertain': ['the 3 in 13'],
            },
          });

      final eq = await service.recognize(ScanSource.camera, imageBytes: _bytes());
      expect(eq.ocr, isNotNull);
      expect(eq.ocr!['confidence'], closeTo(0.62, 1e-9));
      // An edit corrects a misread, so the original read must not survive it.
      expect(eq.copyWith(latex: '2x + 5 = 13').ocr, isNull);
    });

    test('an older backend without an ocr block is not an error', () async {
      final service = FunctionsScannerService(
        (name, data) async => {'latex': '2x + 5 = 13', 'confidence': 0.9},
      );
      final eq = await service.recognize(ScanSource.camera, imageBytes: _bytes());
      expect(eq.ocr, isNull);
    });

    test('throws a typed BackendException when no math is found', () async {
      final service = FunctionsScannerService((name, data) async => {'latex': ''});
      expect(
        () => service.recognize(ScanSource.camera, imageBytes: _bytes()),
        throwsA(isA<BackendException>()),
      );
    });

    test('inferKind classifies common shapes', () {
      expect(FunctionsScannerService.inferKind('x^2 + 1 = 0'),
          EquationKind.quadratic);
      expect(FunctionsScannerService.inferKind(r'\frac{3}{4}'),
          EquationKind.fraction);
      expect(FunctionsScannerService.inferKind('sin(x) = 1'),
          EquationKind.trigonometry);
      expect(FunctionsScannerService.inferKind('2x + 5 = 13'),
          EquationKind.linear);
      expect(FunctionsScannerService.inferKind('2 + 3 times 4'),
          EquationKind.expression);
    });

    test('kindFromTopic preserves the Vision geometry signal (not collapsed to '
        'expression)', () {
      expect(FunctionsScannerService.kindFromTopic('geometry'),
          EquationKind.geometry);
      // Neighbours in the old group still collapse to expression.
      expect(FunctionsScannerService.kindFromTopic('statistics'),
          EquationKind.expression);
    });
  });
}

Uint8List _bytes() => Uint8List.fromList(List<int>.generate(16, (i) => i));
