// Geometry Visual Learning — the three scanned-triangle kinds added after the
// real-device failures: right-triangle trig (side from side + acute angle),
// sine-rule angle (SSA incl. the obtuse branch), and SAS area.
//
// Golden rule throughout: the recognizer only relays the GIVEN facts (and, for
// the sine rule, the problem's own acute/obtuse wording); the app computes the
// unknown, draws the figure from the real numbers, and refuses anything
// inconsistent or genuinely ambiguous.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/geometry_payload_mapper.dart';
import 'package:matheasy/features/result/domain/geometry_models.dart';
import 'package:matheasy/features/result/domain/visual_models.dart'
    show VisualPoint;

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

double _rad(double deg) => deg * math.pi / 180;

GeometryTrigSide _side(String l, GeometryTrigSideRole r, [double? v]) =>
    GeometryTrigSide(label: l, role: r, value: v);

void main() {
  group('rightTriangleTrig computes the missing side', () {
    test('adjacent 40, angle 35° → hypotenuse 40/cos35 (the scanned case)', () {
      final scene = GeometryScene.tryBuildRightTriangleTrig(
        knownAngleDeg: 35,
        knownAngleLabel: 'θ',
        sides: [
          _side('a', GeometryTrigSideRole.adjacent, 40),
          _side('x', GeometryTrigSideRole.hypotenuse),
        ],
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(40 / math.cos(_rad(35)), 1e-9));
      expect(scene.unknownIsAngle, isFalse);
      expect(scene.unknownIsArea, isFalse);
      expect(scene.answerLatex,
          'x = ${(40 / math.cos(_rad(35))).toStringAsFixed(2)}');
    });

    test('adjacent 40, angle 35° → opposite 40·tan35', () {
      final scene = GeometryScene.tryBuildRightTriangleTrig(
        knownAngleDeg: 35,
        knownAngleLabel: 'θ',
        sides: [
          _side('a', GeometryTrigSideRole.adjacent, 40),
          _side('x', GeometryTrigSideRole.opposite),
        ],
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(40 * math.tan(_rad(35)), 1e-9));
    });

    test('hypotenuse 10, angle 30° → opposite 5 (SOH)', () {
      final scene = GeometryScene.tryBuildRightTriangleTrig(
        knownAngleDeg: 30,
        knownAngleLabel: 'A',
        sides: [
          _side('h', GeometryTrigSideRole.hypotenuse, 10),
          _side('x', GeometryTrigSideRole.opposite),
        ],
        unknownLabel: 'x',
      )!;
      expect(scene.unknownValue, closeTo(5, 1e-9));
    });

    test('figure is correct by construction (right angle + given angle)', () {
      final scene = GeometryScene.tryBuildRightTriangleTrig(
        knownAngleDeg: 35,
        knownAngleLabel: 'θ',
        sides: [
          _side('a', GeometryTrigSideRole.adjacent, 40),
          _side('x', GeometryTrigSideRole.hypotenuse),
        ],
        unknownLabel: 'x',
      )!;
      final v = scene.vertices;
      // Right angle at vertex 0, the given 35° at vertex 1.
      expect(_angleAt(v[0], v[1], v[2]), closeTo(90, 0.01));
      expect(_angleAt(v[1], v[0], v[2]), closeTo(35, 0.01));
      // The drawn unknown side (hypotenuse, edge 1: v1→v2) carries the answer.
      expect(_dist(v[1], v[2]), closeTo(scene.unknownValue, 1e-9));
      expect(scene.rightAngleVertices, [0]);
      // Mixed givens: one known angle arc AND labelled sides coexist.
      expect(scene.angles, hasLength(1));
      expect(scene.angles.single.value, 35);
      expect(scene.sides.where((s) => s.isUnknown), hasLength(1));
    });

    test('four canonical steps', () {
      final scene = GeometryScene.tryBuildRightTriangleTrig(
        knownAngleDeg: 35,
        knownAngleLabel: 'θ',
        sides: [
          _side('a', GeometryTrigSideRole.adjacent, 40),
          _side('x', GeometryTrigSideRole.hypotenuse),
        ],
        unknownLabel: 'x',
      )!;
      expect(scene.steps.map((s) => s.focus).toList(), const [
        GeometryStepFocus.known,
        GeometryStepFocus.rule,
        GeometryStepFocus.unknown,
        GeometryStepFocus.answer,
      ]);
      // The ratio shown is cos (CAH: adjacent + hypotenuse).
      expect(scene.steps[1].equationLatex, contains('\\cos'));
    });

    group('golden-rule gate refuses bad data', () {
      test('non-acute angle', () {
        expect(
          GeometryScene.tryBuildRightTriangleTrig(
            knownAngleDeg: 90,
            knownAngleLabel: 'θ',
            sides: [
              _side('a', GeometryTrigSideRole.adjacent, 40),
              _side('x', GeometryTrigSideRole.hypotenuse),
            ],
            unknownLabel: 'x',
          ),
          isNull,
        );
      });

      test('two known sides (that is Pythagoras, not trig)', () {
        expect(
          GeometryScene.tryBuildRightTriangleTrig(
            knownAngleDeg: 35,
            knownAngleLabel: 'θ',
            sides: [
              _side('a', GeometryTrigSideRole.adjacent, 40),
              _side('h', GeometryTrigSideRole.hypotenuse, 50),
            ],
            unknownLabel: 'x',
          ),
          isNull,
        );
      });

      test('duplicate roles', () {
        expect(
          GeometryScene.tryBuildRightTriangleTrig(
            knownAngleDeg: 35,
            knownAngleLabel: 'θ',
            sides: [
              _side('a', GeometryTrigSideRole.adjacent, 40),
              _side('x', GeometryTrigSideRole.adjacent),
            ],
            unknownLabel: 'x',
          ),
          isNull,
        );
      });

      test('contradicts the verified answer', () {
        expect(
          GeometryScene.tryBuildRightTriangleTrig(
            knownAngleDeg: 35,
            knownAngleLabel: 'θ',
            sides: [
              _side('a', GeometryTrigSideRole.adjacent, 40),
              _side('x', GeometryTrigSideRole.hypotenuse),
            ],
            unknownLabel: 'x',
            expectedAnswerLatex: 'x = 99',
          ),
          isNull,
        );
      });

      test('a role-swapped figure at unit magnitudes is caught (relative tol)', () {
        // True answer tan40° ≈ 0.84; a swapped payload computes 1/tan40° ≈
        // 1.19 — a flat 0.5 tolerance would wave that through.
        expect(
          GeometryScene.tryBuildRightTriangleTrig(
            knownAngleDeg: 40,
            knownAngleLabel: 'θ',
            sides: [
              _side('a', GeometryTrigSideRole.opposite, 1),
              _side('x', GeometryTrigSideRole.adjacent),
            ],
            unknownLabel: 'x',
            expectedAnswerLatex: 'x = 0.84',
          ),
          isNull,
        );
      });

      test('label collision (unknown label reused on a known) refuses', () {
        expect(
          GeometryScene.tryBuildRightTriangleTrig(
            knownAngleDeg: 35,
            knownAngleLabel: 'θ',
            sides: [
              _side('x', GeometryTrigSideRole.adjacent, 40),
              _side('x', GeometryTrigSideRole.hypotenuse),
            ],
            unknownLabel: 'x',
          ),
          isNull,
        );
      });
    });

    test('a third labelled-but-valueless side is tolerated (common figures)', () {
      final scene = GeometryScene.tryBuildRightTriangleTrig(
        knownAngleDeg: 35,
        knownAngleLabel: 'θ',
        sides: [
          _side('a', GeometryTrigSideRole.adjacent, 40),
          _side('b', GeometryTrigSideRole.opposite),
          _side('x', GeometryTrigSideRole.hypotenuse),
        ],
        unknownLabel: 'x',
      );
      expect(scene, isNotNull);
      expect(scene!.unknownValue, closeTo(40 / math.cos(_rad(35)), 1e-9));
      expect(scene.unknownSide!.label, 'x');
    });
  });

  group('sineRuleAngle computes the missing angle', () {
    // The scanned case: sides 10 & 16, angle 34° opposite the 10 side, and the
    // problem SAYS the unknown is obtuse.
    final obtuseExpected =
        180 - math.asin(16 * math.sin(_rad(34)) / 10) * 180 / math.pi;

    GeometryScene? build({AngleBranchHint? branch, String? expected}) =>
        GeometryScene.tryBuildSineRuleAngle(
          knownAngleDeg: 34,
          knownAngleLabel: 'C',
          sideOppositeKnown: 10,
          sideOppositeKnownLabel: 'c',
          sideOppositeUnknown: 16,
          sideOppositeUnknownLabel: 'b',
          unknownLabel: 'y',
          branch: branch,
          expectedAnswerLatex: expected,
        );

    test('obtuse branch (the scanned case): y ≈ 116.5°', () {
      final scene = build(branch: AngleBranchHint.obtuse)!;
      expect(scene.unknownValue, closeTo(obtuseExpected, 1e-9));
      expect(scene.unknownIsAngle, isTrue);
      expect(scene.answerLatex,
          'y = ${GeometryScene.formatDegrees(obtuseExpected)}^\\circ');
      // The walkthrough explains the 180° − step.
      expect(scene.steps[2].equationLatex, contains('180^\\circ -'));
    });

    test('acute branch when the problem says acute', () {
      final scene = build(branch: AngleBranchHint.acute)!;
      expect(scene.unknownValue, closeTo(180 - obtuseExpected, 1e-9));
    });

    test('ambiguous with NO hint and no verified answer → refuses', () {
      expect(build(), isNull);
    });

    test('no hint but the verified answer disambiguates', () {
      final scene = build(expected: 'y = 116.5^\\circ')!;
      expect(scene.unknownValue, closeTo(obtuseExpected, 1e-9));
    });

    test('figure is correct by construction (real side lengths)', () {
      final scene = build(branch: AngleBranchHint.obtuse)!;
      final v = scene.vertices;
      // The drawn unknown wedge is the computed obtuse angle…
      expect(_angleAt(v[0], v[1], v[2]), closeTo(obtuseExpected, 0.01));
      // …the known 34° sits at its vertex…
      expect(_angleAt(v[1], v[0], v[2]), closeTo(34, 0.01));
      // …and the labelled sides have their REAL lengths.
      expect(_dist(v[0], v[2]), closeTo(10, 1e-9)); // side opposite the known
      expect(_dist(v[1], v[2]), closeTo(16, 1e-6)); // side opposite the unknown
    });

    test('four canonical steps', () {
      final scene = build(branch: AngleBranchHint.obtuse)!;
      expect(scene.steps.map((s) => s.focus).toList(), const [
        GeometryStepFocus.known,
        GeometryStepFocus.rule,
        GeometryStepFocus.unknown,
        GeometryStepFocus.answer,
      ]);
    });

    group('golden-rule gate refuses bad data', () {
      test('impossible triangle (sin ratio > 1)', () {
        expect(
          GeometryScene.tryBuildSineRuleAngle(
            knownAngleDeg: 60,
            knownAngleLabel: 'A',
            sideOppositeKnown: 5,
            sideOppositeKnownLabel: 'a',
            sideOppositeUnknown: 20,
            sideOppositeUnknownLabel: 'b',
            unknownLabel: 'x',
            branch: AngleBranchHint.acute,
          ),
          isNull,
        );
      });

      test('obtuse hint when the obtuse branch leaves no triangle', () {
        // acute candidate ≈ 70.5°; obtuse 109.5° + 80° ≥ 180 → impossible.
        expect(
          GeometryScene.tryBuildSineRuleAngle(
            knownAngleDeg: 80,
            knownAngleLabel: 'A',
            sideOppositeKnown: 10,
            sideOppositeKnownLabel: 'a',
            sideOppositeUnknown: 9.575,
            sideOppositeUnknownLabel: 'b',
            unknownLabel: 'x',
            branch: AngleBranchHint.obtuse,
          ),
          isNull,
        );
      });

      test('contradicts the verified answer', () {
        expect(build(branch: AngleBranchHint.obtuse, expected: 'y = 63.5'),
            isNull);
      });

      test('label collision (unknown label equals the known angle) refuses', () {
        expect(
          GeometryScene.tryBuildSineRuleAngle(
            knownAngleDeg: 34,
            knownAngleLabel: 'y',
            sideOppositeKnown: 10,
            sideOppositeKnownLabel: 'c',
            sideOppositeUnknown: 16,
            sideOppositeUnknownLabel: 'b',
            unknownLabel: 'y',
            branch: AngleBranchHint.obtuse,
          ),
          isNull,
        );
      });
    });
  });

  group('sasArea computes the area', () {
    // The scanned case: sides 11 & 13, included angle 39°.
    final expectedArea = 0.5 * 11 * 13 * math.sin(_rad(39));

    GeometryScene? build({String? expected}) => GeometryScene.tryBuildSasArea(
          sideA: 11,
          sideALabel: 'a',
          sideB: 13,
          sideBLabel: 'b',
          includedAngleDeg: 39,
          angleLabel: 'C',
          expectedAnswerLatex: expected,
        );

    test('½·11·13·sin39° ≈ 45.00 (the scanned case)', () {
      final scene = build()!;
      expect(scene.unknownValue, closeTo(expectedArea, 1e-9));
      expect(scene.unknownIsArea, isTrue);
      expect(scene.unknownIsAngle, isFalse);
      expect(
        scene.answerLatex,
        '\\text{Area} = ${GeometryScene.formatLength(expectedArea)}',
      );
    });

    test('figure is correct by construction (sides + included angle)', () {
      final scene = build()!;
      final v = scene.vertices;
      expect(_angleAt(v[0], v[1], v[2]), closeTo(39, 0.01));
      expect(_dist(v[0], v[1]), closeTo(11, 1e-9));
      expect(_dist(v[0], v[2]), closeTo(13, 1e-9));
      // No blank mark: the unknown is the interior, not a wedge or side.
      expect(scene.unknownAngle, isNull);
      expect(scene.unknownSide, isNull);
    });

    test('four canonical steps, answer states the area', () {
      final scene = build()!;
      expect(scene.steps.map((s) => s.focus).toList(), const [
        GeometryStepFocus.known,
        GeometryStepFocus.rule,
        GeometryStepFocus.unknown,
        GeometryStepFocus.answer,
      ]);
      expect(scene.steps.last.detail, contains('area'));
      // VoiceOver: never spoils the answer before the answer beat.
      expect(scene.semanticsForStep(0), isNot(contains('45')));
      expect(scene.semanticsForStep(3), contains('area'));
    });

    group('golden-rule gate refuses bad data', () {
      test('degenerate angle', () {
        expect(
          GeometryScene.tryBuildSasArea(
            sideA: 11,
            sideALabel: 'a',
            sideB: 13,
            sideBLabel: 'b',
            includedAngleDeg: 180,
            angleLabel: 'C',
          ),
          isNull,
        );
      });

      test('non-positive side', () {
        expect(
          GeometryScene.tryBuildSasArea(
            sideA: 0,
            sideALabel: 'a',
            sideB: 13,
            sideBLabel: 'b',
            includedAngleDeg: 39,
            angleLabel: 'C',
          ),
          isNull,
        );
      });

      test('contradicts the verified answer', () {
        expect(build(expected: '100'), isNull);
      });

      test('a \\frac expected answer is parsed as a VALUE, not its numerator',
          () {
        // Area ≈ 45.00. An expected '\frac{1}{2}' means 0.5 — the old
        // first-number grab would read 1 and (for a 1-ish computed value)
        // falsely pass; here it must reject 45 vs 0.5.
        expect(build(expected: r'\text{Area} = \frac{1}{2}'), isNull);
      });

      test('an unparseable symbolic expected answer skips the gate', () {
        // A √-form can't be read into one number reliably — the gate is
        // skipped (permissive) rather than misparsed into a wrong rejection.
        expect(build(expected: r'\frac{45\sqrt{3}}{2}'), isNotNull);
      });
    });
  });

  group('GeometryPayloadMapper parses the new kinds', () {
    test('rightTriangleTrig payload from the recognizer', () {
      final scene = GeometryPayloadMapper.parse({
        'kind': 'rightTriangleTrig',
        'unknown': 'x',
        'knownAngle': {'label': 'θ', 'value': 35},
        'sides': [
          {'label': 'a', 'role': 'adjacent', 'value': 40},
          {'label': 'x', 'role': 'hypotenuse'},
        ],
      });
      expect(scene, isNotNull);
      expect(scene!.kind, GeometrySceneKind.rightTriangleTrig);
      expect(scene.unknownValue, closeTo(40 / math.cos(_rad(35)), 1e-9));
    });

    test('sineRuleAngle payload with the obtuse branch', () {
      final scene = GeometryPayloadMapper.parse({
        'kind': 'sineRuleAngle',
        'unknown': 'y',
        'knownAngle': {'label': 'C', 'value': 34},
        'sideOppositeKnown': {'label': 'c', 'value': 10},
        'sideOppositeUnknown': {'label': 'b', 'value': 16},
        'angleBranch': 'obtuse',
      });
      expect(scene, isNotNull);
      expect(scene!.kind, GeometrySceneKind.sineRuleAngle);
      expect(scene.unknownValue, greaterThan(90)); // the obtuse branch
    });

    test('sineRuleAngle payload WITHOUT a branch on an ambiguous case → null',
        () {
      expect(
        GeometryPayloadMapper.parse({
          'kind': 'sineRuleAngle',
          'unknown': 'y',
          'knownAngle': {'label': 'C', 'value': 34},
          'sideOppositeKnown': {'label': 'c', 'value': 10},
          'sideOppositeUnknown': {'label': 'b', 'value': 16},
        }),
        isNull,
      );
    });

    test('sasArea payload from the recognizer', () {
      final scene = GeometryPayloadMapper.parse({
        'kind': 'sasArea',
        'unknown': 'Area',
        'sides': [
          {'label': 'a', 'value': 11},
          {'label': 'b', 'value': 13},
        ],
        'includedAngle': {'label': 'C', 'value': 39},
      });
      expect(scene, isNotNull);
      expect(scene!.kind, GeometrySceneKind.sasArea);
      expect(scene.unknownValue, closeTo(0.5 * 11 * 13 * math.sin(_rad(39)), 1e-9));
    });

    test('a degree-symbol string value is coerced, not fatal', () {
      final scene = GeometryPayloadMapper.parse({
        'kind': 'rightTriangleTrig',
        'unknown': 'x',
        'knownAngle': {'label': 'θ', 'value': '35°'},
        'sides': [
          {'label': 'a', 'role': 'adjacent', 'value': 40},
          {'label': 'x', 'role': 'hypotenuse'},
        ],
      });
      expect(scene, isNotNull);
      expect(scene!.unknownValue, closeTo(40 / math.cos(_rad(35)), 1e-9));
    });

    test('sasArea with a SIDE-style unknown (misfiled cosine rule) rejects',
        () {
      expect(
        GeometryPayloadMapper.parse({
          'kind': 'sasArea',
          'unknown': 'x',
          'sides': [
            {'label': 'a', 'value': 11},
            {'label': 'b', 'value': 13},
          ],
          'includedAngle': {'label': 'C', 'value': 39},
        }),
        isNull,
      );
    });

    test('malformed payloads reject', () {
      expect(
        GeometryPayloadMapper.parse({
          'kind': 'rightTriangleTrig',
          'unknown': 'x',
          'knownAngle': {'label': 'θ', 'value': 35},
          'sides': [
            {'label': 'a', 'role': 'leg', 'value': 40}, // Pythagoras role
            {'label': 'x', 'role': 'hypotenuse'},
          ],
        }),
        isNull,
      );
      expect(
        GeometryPayloadMapper.parse({
          'kind': 'sasArea',
          'sides': [
            {'label': 'a', 'value': 11},
          ], // only one side
          'includedAngle': {'label': 'C', 'value': 39},
        }),
        isNull,
      );
      expect(
        GeometryPayloadMapper.parse({
          'kind': 'sineRuleAngle',
          'knownAngle': {'label': 'C', 'value': 34},
          // missing the side objects
        }),
        isNull,
      );
    });
  });
}
