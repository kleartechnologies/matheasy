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
  group('SolveResponseMapper', () {
    test('maps the full solveEquation payload onto ResultData', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'type': 'linear',
        'difficulty': 'easy',
        'answerLatex': 'x = 4',
        'verifyText': '2(4) + 5 = 13 ✓',
        'numiIntro': 'Here we go!',
        'steps': [
          {
            'title': 'Subtract 5',
            'operationLabel': '− 5',
            'resultLatex': '2x = 8',
            'detail': 'Undo the + 5.',
          },
          {'title': 'Divide by 2', 'resultLatex': 'x = 4', 'detail': 'Undo ×2.'},
        ],
        'explanations': [
          {'mode': 'simple', 'body': 'Isolate x.', 'points': ['a', 'b']},
          {'mode': 'teacher', 'body': 'Inverse ops.', 'points': ['x']},
          {'mode': 'exam', 'body': 'Steps.', 'points': ['x = 4']},
        ],
        'methods': [
          {
            'name': 'Balance',
            'subtitle': 'Both sides',
            'description': 'Do the same to both sides.',
            'advantages': ['reliable'],
            'whenToUse': 'always',
            'steps': ['2x = 8', 'x = 4'],
            'recommended': true,
          },
        ],
        'practice': [
          {'questionLatex': 'x + 4 = 9', 'difficulty': 'easy', 'xpReward': 15},
        ],
      });

      expect(result.equation, _equation);
      expect(result.type, ResultType.linear);
      expect(result.difficulty, Difficulty.easy);
      expect(result.answerLatex, 'x = 4');
      expect(result.steps, hasLength(2));
      expect(result.steps.first.operationLabel, '− 5');
      expect(result.steps[1].operationLabel, isNull);
      expect(result.explanations.map((e) => e.mode),
          [ExplanationMode.simple, ExplanationMode.teacher, ExplanationMode.exam]);
      expect(result.methods.single.recommended, isTrue);
      expect(result.practice.single.xpReward, 15);
    });

    test('degrades gracefully on missing / unknown fields', () {
      final result = SolveResponseMapper.toResultData(_equation, {
        'type': 'nonsense',
        'answerLatex': 'x = 1',
        'explanations': [
          {'mode': 'weird', 'body': 'x', 'points': <String>[]},
        ],
      });
      expect(result.type, ResultType.expression); // unknown → fallback
      expect(result.difficulty, Difficulty.medium);
      expect(result.steps, isEmpty);
      expect(result.explanations, isEmpty); // unknown mode dropped
      expect(result.numiIntro, isNotEmpty); // fallback text
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
  });
}

Uint8List _bytes() => Uint8List.fromList(List<int>.generate(16, (i) => i));
