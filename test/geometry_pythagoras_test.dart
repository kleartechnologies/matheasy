// Geometry Visual Learning — right-triangle Pythagoras (side lengths).
//
// The deterministic length engine: the app computes the missing side and builds
// a correct-by-construction right triangle. Golden rule — the LLM only relays
// the given sides + which one is the hypotenuse; the app does the arithmetic.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/geometry_payload_mapper.dart';
import 'package:matheasy/features/result/domain/geometry_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart' show VisualPoint;

double _dist(VisualPoint a, VisualPoint b) =>
    math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));

/// The angle (degrees) at vertex [v] between the rays to [p1] and [p2].
double _angleAt(VisualPoint v, VisualPoint p1, VisualPoint p2) {
  final a = math.atan2(p1.y - v.y, p1.x - v.x);
  final b = math.atan2(p2.y - v.y, p2.x - v.x);
  var d = (a - b).abs();
  if (d > math.pi) d = 2 * math.pi - d;
  return d * 180 / math.pi;
}

GeometryKnownSide _leg(String l, [double? v]) =>
    GeometryKnownSide(label: l, role: GeometrySideRole.leg, value: v);
GeometryKnownSide _hyp(String l, [double? v]) =>
    GeometryKnownSide(label: l, role: GeometrySideRole.hypotenuse, value: v);

void main() {
  group('Pythagoras computes the missing side', () {
    test('unknown hypotenuse: legs 6, 8 → 10', () {
      final scene = GeometryScene.tryBuildPythagoras(
        sides: [_leg('a', 6), _leg('b', 8), _hyp('x')],
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(10, 1e-9));
      expect(scene.answerLatex, r'x = 10'); // no degree symbol
      expect(scene.unknownIsAngle, isFalse);
    });

    test('unknown leg: hypotenuse 10, other leg 6 → 8 (the scanned case)', () {
      final scene = GeometryScene.tryBuildPythagoras(
        sides: [_leg('a', 6), _hyp('c', 10), _leg('x')],
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(8, 1e-9));
    });

    test('irrational answer keeps two decimals', () {
      final scene = GeometryScene.tryBuildPythagoras(
        sides: [_leg('a', 6), _leg('b', 10), _hyp('x')],
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(math.sqrt(136), 1e-9));
      expect(scene.answerLatex, 'x = ${math.sqrt(136).toStringAsFixed(2)}');
    });
  });

  group('The triangle is correct by construction', () {
    test('sides + right angle actually match the numbers', () {
      final scene = GeometryScene.tryBuildPythagoras(
        sides: [_leg('a', 6), _leg('b', 8), _hyp('x')],
        unknownLabel: 'x',
      )!;
      final v = scene.vertices; // [C(right angle), A, B]
      // The right angle sits at vertex 0.
      expect(scene.rightAngleVertices, [0]);
      expect(_angleAt(v[0], v[1], v[2]), closeTo(90, 0.01));
      // Legs 6 and 8, hypotenuse 10, drawn to scale.
      final lengths = {_dist(v[0], v[1]), _dist(v[0], v[2]), _dist(v[1], v[2])};
      expect(lengths.any((l) => (l - 6).abs() < 0.01), isTrue);
      expect(lengths.any((l) => (l - 8).abs() < 0.01), isTrue);
      expect(lengths.any((l) => (l - 10).abs() < 0.01), isTrue);
    });

    test('the four canonical steps are present and end on the answer', () {
      final scene = GeometryScene.tryBuildPythagoras(
        sides: [_leg('a', 6), _leg('b', 8), _hyp('x')],
        unknownLabel: 'x',
      )!;
      expect(scene.steps.map((s) => s.focus), <GeometryStepFocus>[
        GeometryStepFocus.known,
        GeometryStepFocus.rule,
        GeometryStepFocus.unknown,
        GeometryStepFocus.answer,
      ]);
      expect(scene.steps.last.equationLatex, r'x = 10');
    });
  });

  group('The golden-rule gate refuses bad data', () {
    test('a leg larger than the hypotenuse is impossible', () {
      expect(
        GeometryScene.tryBuildPythagoras(
          sides: [_leg('a', 12), _hyp('c', 10), _leg('x')],
          unknownLabel: 'x',
        ),
        isNull, // 12 > 10 ⇒ no real right triangle
      );
    });

    test('missing hypotenuse role is rejected', () {
      expect(
        GeometryScene.tryBuildPythagoras(
          sides: [_leg('a', 6), _leg('b', 8), _leg('x')], // no hypotenuse
          unknownLabel: 'x',
        ),
        isNull,
      );
    });

    test('a computed answer contradicting the verified answer is rejected', () {
      expect(
        GeometryScene.tryBuildPythagoras(
          sides: [_leg('a', 6), _leg('b', 8), _hyp('x')],
          unknownLabel: 'x',
          expectedAnswerLatex: 'x = 99', // solver disagrees with 10
        ),
        isNull,
      );
    });
  });

  group('GeometryPayloadMapper parses both angle + Pythagoras payloads', () {
    test('a Pythagoras payload from the recognizer', () {
      final scene = GeometryPayloadMapper.parse({
        'kind': 'rightTrianglePythagoras',
        'unknown': 'x',
        'sides': [
          {'label': 'a', 'role': 'leg', 'value': 6},
          {'label': 'c', 'role': 'hypotenuse', 'value': 10},
          {'label': 'x', 'role': 'leg'}, // no value ⇒ unknown
        ],
      });
      expect(scene, isNotNull);
      expect(scene!.unknownValue, closeTo(8, 1e-9));
      expect(scene.kind, GeometrySceneKind.rightTrianglePythagoras);
    });

    test('an angle payload still maps (triangle 60+40→80)', () {
      final scene = GeometryPayloadMapper.parse({
        'kind': 'triangleAngles',
        'unknown': 'x',
        'knownAngles': [
          {'label': 'A', 'value': 60},
          {'label': 'B', 'value': 40},
        ],
      });
      expect(scene!.unknownValue, closeTo(80, 1e-9));
    });

    test('a polygon payload reads polygonSides', () {
      final scene = GeometryPayloadMapper.parse({
        'kind': 'polygonAngles',
        'unknown': 'e',
        'polygonSides': 5,
        'knownAngles': [
          {'label': 'a', 'value': 100},
          {'label': 'b', 'value': 110},
          {'label': 'c', 'value': 120},
          {'label': 'd', 'value': 90},
        ],
      });
      expect(scene!.unknownValue, closeTo(120, 1e-9));
    });

    test('malformed / absent geometry → null', () {
      expect(GeometryPayloadMapper.parse(null), isNull);
      expect(GeometryPayloadMapper.parse({'kind': 'nonsense'}), isNull);
      expect(
        GeometryPayloadMapper.parse({
          'kind': 'rightTrianglePythagoras',
          'sides': [
            {'label': 'a', 'role': 'wat', 'value': 6}, // bad role
          ],
        }),
        isNull,
      );
    });
  });
}
