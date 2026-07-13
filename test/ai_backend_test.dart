// Tests for the real-AI backend integration: the JSON → domain mappers for the
// solve/tutor/scan Cloud Functions, and the FunctionsScannerService flow with a
// fake callable. The mapping is pure, so it's tested without the cloud_functions
// plugin (the services take an injected call function).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/features/result/application/functions_solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/application/functions_scanner_service.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/tutor/application/functions_tutor_service.dart';
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
