// Geometry Visual Learning — the deterministic scene solver.
//
// THE GOLDEN RULE for geometry: the app computes the missing measure and builds
// the figure from the numbers; the LLM only relays the givens. These tests pin
// that behaviour — correct answers, correct-by-construction figures, the four
// canonical steps, and (critically) that inconsistent or answer-contradicting
// data is REFUSED (returns null → the tab falls back) rather than drawn wrong.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/geometry_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart' show VisualPoint;

List<GeometryKnownAngle> _knowns(List<(String, double)> xs) =>
    [for (final x in xs) GeometryKnownAngle(label: x.$1, value: x.$2)];

/// The interior angle (degrees) at [v] between the rays to [p1] and [p2].
double _angleAt(VisualPoint v, VisualPoint p1, VisualPoint p2) {
  final a = math.atan2(p1.y - v.y, p1.x - v.x);
  final b = math.atan2(p2.y - v.y, p2.x - v.x);
  var d = (a - b).abs();
  if (d > math.pi) d = 2 * math.pi - d;
  return d * 180 / math.pi;
}

void main() {
  group('Sum rules compute the unknown', () {
    test('triangle 60 + 40 → 80', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.triangleAngles,
        knownAngles: _knowns([('A', 60), ('B', 40)]),
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(80, 1e-9));
      expect(scene.answerLatex, r'x = 80^\circ');
      expect(scene.unknownAngle!.isUnknown, isTrue);
    });

    test('quadrilateral 90 + 90 + 90 → 90', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.quadrilateralAngles,
        knownAngles: _knowns([('A', 90), ('B', 90), ('C', 90)]),
        unknownLabel: 'd',
      )!;
      expect(scene.unknownValue, closeTo(90, 1e-9));
    });

    test('pentagon interior angles sum to 540', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.polygonAngles,
        knownAngles: _knowns([('a', 100), ('b', 110), ('c', 120), ('d', 90)]),
        unknownLabel: 'e',
        sides: 5,
      )!;
      expect(scene.unknownValue, closeTo(120, 1e-9)); // 540 − 420
      expect(scene.vertices.length, 5);
    });

    test('angles on a straight line 130 → 50', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.straightLineAngles,
        knownAngles: _knowns([('a', 130)]),
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(50, 1e-9));
    });

    test('angles around a point 120 + 140 → 100', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.anglesAroundPoint,
        knownAngles: _knowns([('a', 120), ('b', 140)]),
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(100, 1e-9));
    });

    test('isosceles with only the apex → equal base angles', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.isoscelesTriangle,
        knownAngles: _knowns([('apex', 40)]),
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(70, 1e-9)); // (180 − 40) / 2
      expect(scene.tickEdges, isNotEmpty); // equal sides are marked
    });
  });

  group('Relation rules compute the unknown', () {
    test('parallel lines, alternate angles are equal', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.parallelLines,
        knownAngles: _knowns([('a', 65)]),
        unknownLabel: 'x',
        relation: GeometryRelation.equal,
        relationReference: 'a',
      )!;
      expect(scene.unknownValue, closeTo(65, 1e-9));
    });

    test('parallel lines, co-interior angles are supplementary', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.parallelLines,
        knownAngles: _knowns([('a', 110)]),
        unknownLabel: 'x',
        relation: GeometryRelation.supplementary,
        relationReference: 'a',
      )!;
      expect(scene.unknownValue, closeTo(70, 1e-9));
    });

    test('circle, angle at centre is twice the circumference', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.circleAngle,
        knownAngles: _knowns([('a', 40)]),
        unknownLabel: 'x',
        relation: GeometryRelation.doubleOf,
        relationReference: 'a',
      )!;
      expect(scene.unknownValue, closeTo(80, 1e-9));
      expect(scene.circleCenterVertex, isNotNull);
    });

    test('circle, angle at circumference is half the centre', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.circleAngle,
        knownAngles: _knowns([('a', 100)]),
        unknownLabel: 'x',
        relation: GeometryRelation.halfOf,
        relationReference: 'a',
      )!;
      expect(scene.unknownValue, closeTo(50, 1e-9));
    });
  });

  group('Figures are correct by construction', () {
    test('the triangle actually has the solved angles', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.triangleAngles,
        knownAngles: _knowns([('A', 60), ('B', 40)]),
        unknownLabel: 'x',
      )!;
      final v = scene.vertices;
      // Angle at each vertex, measured off the constructed points.
      expect(_angleAt(v[0], v[1], v[2]), closeTo(60, 0.01));
      expect(_angleAt(v[1], v[2], v[0]), closeTo(40, 0.01));
      expect(_angleAt(v[2], v[0], v[1]), closeTo(80, 0.01));
    });

    test('straight-line rays span exactly 180°', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.straightLineAngles,
        knownAngles: _knowns([('a', 130)]),
        unknownLabel: 'x',
      )!;
      // The two given gaps (130 + 50) must place the fan ends on a line.
      final o = scene.vertices[0];
      final first = scene.vertices[1];
      final last = scene.vertices.last;
      expect(_angleAt(o, first, last), closeTo(180, 0.01));
    });

    // Regression: the parallel-lines UNKNOWN arc must open to the labelled
    // value, not its supplement (the ray-2 = trDn fix).
    test('parallel alternate: both drawn arcs equal the labelled angle', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.parallelLines,
        knownAngles: _knowns([('a', 65)]),
        unknownLabel: 'x',
        relation: GeometryRelation.equal,
        relationReference: 'a',
      )!;
      final v = scene.vertices;
      final known = scene.angles.firstWhere((a) => !a.isUnknown);
      final unknown = scene.angles.firstWhere((a) => a.isUnknown);
      expect(_angleAt(v[known.vertex], v[known.ray1], v[known.ray2]),
          closeTo(65, 0.01));
      expect(_angleAt(v[unknown.vertex], v[unknown.ray1], v[unknown.ray2]),
          closeTo(65, 0.01)); // alternate ⇒ equal, and DRAWN equal
    });

    test('parallel co-interior: the drawn arc opens to 180 − φ', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.parallelLines,
        knownAngles: _knowns([('a', 110)]),
        unknownLabel: 'x',
        relation: GeometryRelation.supplementary,
        relationReference: 'a',
      )!;
      final v = scene.vertices;
      final unknown = scene.angles.firstWhere((a) => a.isUnknown);
      expect(_angleAt(v[unknown.vertex], v[unknown.ray1], v[unknown.ray2]),
          closeTo(70, 0.01));
    });

    test('circle: drawn central + inscribed arcs match the theorem', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.circleAngle,
        knownAngles: _knowns([('a', 40)]),
        unknownLabel: 'x',
        relation: GeometryRelation.doubleOf,
        relationReference: 'a',
      )!;
      final v = scene.vertices;
      final centre = scene.angles.firstWhere((a) => a.isUnknown); // the centre
      final inscribed = scene.angles.firstWhere((a) => !a.isUnknown);
      expect(_angleAt(v[centre.vertex], v[centre.ray1], v[centre.ray2]),
          closeTo(80, 0.01));
      expect(
          _angleAt(v[inscribed.vertex], v[inscribed.ray1], v[inscribed.ray2]),
          closeTo(40, 0.01));
    });
  });

  group('The four canonical steps', () {
    test('are always present and ordered known → rule → unknown → answer', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.triangleAngles,
        knownAngles: _knowns([('A', 60), ('B', 40)]),
        unknownLabel: 'x',
      )!;
      expect(scene.steps.map((s) => s.focus).toList(), <GeometryStepFocus>[
        GeometryStepFocus.known,
        GeometryStepFocus.rule,
        GeometryStepFocus.unknown,
        GeometryStepFocus.answer,
      ]);
      // The answer step carries the final equation; the rule step the sum.
      expect(scene.steps.last.equationLatex, r'x = 80^\circ');
      expect(scene.steps[1].equationLatex, contains('180'));
    });
  });

  group('The golden-rule gate refuses bad data (→ null → fallback)', () {
    test('inconsistent givens leave no valid angle', () {
      expect(
        GeometryScene.tryBuild(
          kind: GeometrySceneKind.triangleAngles,
          knownAngles: _knowns([('A', 150), ('B', 50)]), // sum ≥ 180
          unknownLabel: 'x',
        ),
        isNull,
      );
    });

    test('a computed answer that disagrees with the verified answer', () {
      expect(
        GeometryScene.tryBuild(
          kind: GeometrySceneKind.triangleAngles,
          knownAngles: _knowns([('A', 60), ('B', 40)]),
          unknownLabel: 'x',
          expectedAnswerLatex: r'x = 90^\circ', // solver says 90, we get 80
        ),
        isNull,
      );
    });

    test('a matching verified answer is accepted', () {
      expect(
        GeometryScene.tryBuild(
          kind: GeometrySceneKind.triangleAngles,
          knownAngles: _knowns([('A', 60), ('B', 40)]),
          unknownLabel: 'x',
          expectedAnswerLatex: r'x = 80^\circ',
        ),
        isNotNull,
      );
    });

    test('a triangle with the wrong number of givens', () {
      expect(
        GeometryScene.tryBuild(
          kind: GeometrySceneKind.triangleAngles,
          knownAngles: _knowns([('A', 60)]), // needs two
          unknownLabel: 'x',
        ),
        isNull,
      );
    });

    test('a non-finite / out-of-range given', () {
      expect(
        GeometryScene.tryBuild(
          kind: GeometrySceneKind.triangleAngles,
          knownAngles: _knowns([('A', 60), ('B', 400)]),
          unknownLabel: 'x',
        ),
        isNull,
      );
    });

    test('a circle relation this construction cannot draw (same-segment)', () {
      // circleAngle only draws centre/circumference; `equal` (same segment)
      // would otherwise be mis-built, so it must fall back.
      expect(
        GeometryScene.tryBuild(
          kind: GeometrySceneKind.circleAngle,
          knownAngles: _knowns([('a', 40)]),
          unknownLabel: 'x',
          relation: GeometryRelation.equal,
          relationReference: 'a',
        ),
        isNull,
      );
    });

    test('a reflex central angle cannot be drawn faithfully', () {
      // doubleOf with a 100° circumference ⇒ 200° centre (reflex) → fall back.
      expect(
        GeometryScene.tryBuild(
          kind: GeometrySceneKind.circleAngle,
          knownAngles: _knowns([('a', 100)]),
          unknownLabel: 'x',
          relation: GeometryRelation.doubleOf,
          relationReference: 'a',
        ),
        isNull,
      );
    });
  });

  group('Step-aware semantics never spoils the answer', () {
    test('the answer appears only on the answer beat', () {
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.triangleAngles,
        knownAngles: _knowns([('A', 60), ('B', 40)]),
        unknownLabel: 'x',
      )!;
      // Steps 0–2 must not reveal the answer; the final step must. (Match the
      // answer PHRASE — the rule text "sum to 180°" harmlessly contains "80".)
      for (var i = 0; i < 3; i++) {
        expect(scene.semanticsForStep(i), isNot(contains('is 80 degrees')));
        expect(scene.semanticsForStep(i), contains('Find the missing angle'));
      }
      expect(scene.semanticsForStep(3), contains('is 80 degrees'));
    });
  });

  group('Formatting', () {
    test('whole degrees stay integers, fractions keep one decimal', () {
      expect(GeometryScene.formatDegrees(80), '80');
      expect(GeometryScene.formatDegrees(79.5), '79.5');
      final scene = GeometryScene.tryBuild(
        kind: GeometrySceneKind.triangleAngles,
        knownAngles: _knowns([('A', 60.5), ('B', 40)]),
        unknownLabel: 'x',
      )!;
      expect(scene.answerLatex, r'x = 79.5^\circ');
    });
  });
}
