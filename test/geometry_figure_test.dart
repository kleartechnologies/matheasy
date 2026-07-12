// Stage 4 — geometry figures are FAITHFUL and never spoil the answer.
//
// The golden rule: every figure is built by its rule template from the SAME
// numbers the template generated, so a drawn 86° angle IS 86°. These tests
// prove it *computationally* — they recover each drawn angle/length straight
// from the figure's coordinates and assert it equals the generated label — and
// prove the "givaway" invariant (the UNKNOWN the question asks for is never
// labelled). Plus a loud GUARD that no geometry skill can drift to the LLM tier
// (whose generator has no figure, so it would emit "the shape shown" nonsense).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/practice/application/engine/parameter_generator.dart';
import 'package:matheasy/features/practice/application/engine/rule_based_generator.dart';
import 'package:matheasy/features/practice/domain/generation_tier.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_figure.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_skill.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';

const _generator = RuleBasedGenerator();

/// Every (skill, difficulty, seed) combo, so the assertions see a wide spread
/// of generated parameters rather than one lucky draw.
Iterable<PracticeQuestion> _questions(PracticeSkill skill) sync* {
  for (final d in PracticeDifficulty.values) {
    for (var seed = 0; seed < 40; seed++) {
      final g = _generator.generate(skill, d, ParameterGenerator(math.Random(seed)), 'q$seed');
      if (g != null) yield g.question;
    }
  }
}

double _deg(double rad) => rad * 180 / math.pi;

/// Interior angle (degrees) at polygon vertex [i], recovered from coordinates.
double _angleAt(List<PracticeFigurePoint> v, int i) {
  final n = v.length;
  final c = v[i], p = v[(i - 1 + n) % n], q = v[(i + 1) % n];
  final ux = p.x - c.x, uy = p.y - c.y;
  final wx = q.x - c.x, wy = q.y - c.y;
  final dot = ux * wx + uy * wy;
  final mag = math.sqrt(ux * ux + uy * uy) * math.sqrt(wx * wx + wy * wy);
  return _deg(math.acos((dot / mag).clamp(-1.0, 1.0)));
}

/// Angle P-O-Q (degrees) at [o], for non-polygon point sets (straight line).
double _angleBetween(PracticeFigurePoint o, PracticeFigurePoint pt, PracticeFigurePoint qt) {
  final ux = pt.x - o.x, uy = pt.y - o.y;
  final wx = qt.x - o.x, wy = qt.y - o.y;
  final dot = ux * wx + uy * wy;
  final mag = math.sqrt(ux * ux + uy * uy) * math.sqrt(wx * wx + wy * wy);
  return _deg(math.acos((dot / mag).clamp(-1.0, 1.0)));
}

double _length(PracticeFigurePoint a, PracticeFigurePoint b) =>
    math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

/// Parses the leading integer out of a label like "86°" / "12" (or null).
int? _labelInt(String s) {
  final m = RegExp(r'-?\d+').firstMatch(s);
  return m == null ? null : int.parse(m.group(0)!);
}

int _answerInt(PracticeQuestion q) => int.parse(q.acceptedAnswers.first.replaceAll(RegExp(r'[^0-9-]'), ''));

void main() {
  group('faithfulness — the drawn figure equals the generated numbers', () {
    test('triangle angle sum: the two labelled base angles ARE those angles', () {
      for (final q in _questions(PracticeSkill.triangleAngle)) {
        final f = q.figure!;
        expect(f.kind, PracticeFigureKind.polygon);
        for (final i in [0, 1]) {
          final labelled = _labelInt(f.angleLabels[i])!;
          expect(_angleAt(f.vertices, i), closeTo(labelled.toDouble(), 0.5),
              reason: 'drawn angle at vertex $i must equal its $labelled° label');
        }
      }
    });

    test('isosceles: the drawn apex angle IS the labelled apex, and the two '
        'tick-marked sides are actually equal', () {
      for (final q in _questions(PracticeSkill.isoscelesTriangle)) {
        final f = q.figure!;
        final apex = _labelInt(f.angleLabels[2])!;
        expect(_angleAt(f.vertices, 2), closeTo(apex.toDouble(), 0.5),
            reason: 'drawn apex must equal the $apex° label');
        // Edges 1→2 and 2→0 wear ticks (the equal legs) — prove they're equal.
        final leg1 = _length(f.vertices[1], f.vertices[2]);
        final leg2 = _length(f.vertices[2], f.vertices[0]);
        expect(leg1, closeTo(leg2, 1e-9), reason: 'tick-marked sides must be congruent');
        expect(f.tickEdges.keys.toSet(), {1, 2});
      }
    });

    test('area (base×height): base leg == base, height leg == height', () {
      for (final q in _questions(PracticeSkill.triangleAreaBaseHeight)) {
        final f = q.figure!;
        final base = _labelInt(f.sideLabels[0])!;
        final height = _labelInt(f.sideLabels[2])!;
        expect(_length(f.vertices[0], f.vertices[1]), closeTo(base.toDouble(), 1e-9));
        expect(_length(f.vertices[2], f.vertices[0]), closeTo(height.toDouble(), 1e-9));
      }
    });

    test('straight line: the drawn given angle IS the labelled given', () {
      for (final q in _questions(PracticeSkill.anglesStraightLine)) {
        final f = q.figure!;
        expect(f.kind, PracticeFigureKind.straightLineAngles);
        final given = _labelInt(f.lineGivenLabel!)!;
        // Points are [A, O, B, C]; the labelled angle is A-O-C.
        final drawn = _angleBetween(f.vertices[1], f.vertices[0], f.vertices[3]);
        expect(drawn, closeTo(given.toDouble(), 0.5));
      }
    });

    test('rectangle: the two labelled sides ARE those lengths (guards a swapped '
        'length/width label)', () {
      for (final q in _questions(PracticeSkill.rectangleArea)) {
        final f = q.figure!;
        expect(f.kind, PracticeFigureKind.polygon);
        final l = _labelInt(f.sideLabels[0])!; // bottom edge 0→1
        final w = _labelInt(f.sideLabels[1])!; // right edge 1→2
        expect(_length(f.vertices[0], f.vertices[1]), closeTo(l.toDouble(), 1e-9));
        expect(_length(f.vertices[1], f.vertices[2]), closeTo(w.toDouble(), 1e-9));
      }
    });

    test('pythagoras: the two labelled legs ARE those lengths (guards a swapped '
        'leg label — every triple has leg0 < leg1)', () {
      for (final q in _questions(PracticeSkill.pythagoras)) {
        final f = q.figure!;
        final a = _labelInt(f.sideLabels[0])!; // base leg, edge 0→1
        final b = _labelInt(f.sideLabels[2])!; // height leg, edge 2→0
        expect(_length(f.vertices[0], f.vertices[1]), closeTo(a.toDouble(), 1e-9));
        expect(_length(f.vertices[2], f.vertices[0]), closeTo(b.toDouble(), 1e-9));
      }
    });
  });

  group('the figure poses the problem, it never spoils it (UNKNOWN left blank)', () {
    test('triangle: the apex (the answer) slot is blank', () {
      for (final q in _questions(PracticeSkill.triangleAngle)) {
        expect(q.figure!.angleLabels[2], isEmpty);
      }
    });

    test('isosceles: both base angles (the answer) are blank', () {
      for (final q in _questions(PracticeSkill.isoscelesTriangle)) {
        expect(q.figure!.angleLabels[0], isEmpty);
        expect(q.figure!.angleLabels[1], isEmpty);
      }
    });

    test('pythagoras & area: the hypotenuse side slot is blank', () {
      for (final skill in [PracticeSkill.pythagoras, PracticeSkill.triangleAreaBaseHeight]) {
        for (final q in _questions(skill)) {
          expect(q.figure!.sideLabels[1], isEmpty);
        }
      }
    });

    test('straight line: only the given is labelled (no unknown-angle field)', () {
      for (final q in _questions(PracticeSkill.anglesStraightLine)) {
        final f = q.figure!;
        expect(f.lineGivenLabel, isNotNull);
        expect(f.angleLabels, isEmpty); // the unknown never gets its own label
      }
    });

    test('circle: only the radius is labelled; the diameter (answer) is not', () {
      for (final q in _questions(PracticeSkill.circleMeasures)) {
        final f = q.figure!;
        expect(_answerInt(q), isNot(equals(_labelInt(f.circleLabel!))),
            reason: 'the diameter (answer) must differ from the labelled radius');
      }
    });

    test('quadrilateral: text-only (no figure — a quad is not fixed by its '
        'angles, so drawing one faithfully is impossible)', () {
      for (final q in _questions(PracticeSkill.quadrilateralAngles)) {
        expect(q.figure, isNull);
      }
    });
  });

  group('the base×height figure shows a REAL perpendicular height', () {
    test('right-angle mark at the base and a vertical leg of exactly `height`', () {
      for (final q in _questions(PracticeSkill.triangleAreaBaseHeight)) {
        final f = q.figure!;
        expect(f.rightAngleVertices, contains(0)); // marked right angle
        final height = _labelInt(f.sideLabels[2])!;
        final v0 = f.vertices[0], v2 = f.vertices[2];
        expect(v0.x, closeTo(v2.x, 1e-9), reason: 'the height leg must be vertical');
        expect(_length(v0, v2), closeTo(height.toDouble(), 1e-9));
        // And the drawn right angle really is 90°.
        expect(_angleAt(f.vertices, 0), closeTo(90, 1e-6));
      }
    });
  });

  group('GUARD — no geometry skill may drift to the LLM tier', () {
    test('every geometry skill is GenerationTier.ruleBased', () {
      final geometry = PracticeSkill.forTopic(PracticeTopic.geometry);
      expect(geometry, isNotEmpty);
      for (final skill in geometry) {
        expect(skill.tier, GenerationTier.ruleBased,
            reason: '${skill.id} must stay ruleBased — the .ai path has no figure '
                'guard and would emit "the shape shown" questions with no shape.');
      }
    });

    test('every geometry skill actually has a rule template', () {
      const gen = RuleBasedGenerator();
      for (final skill in PracticeSkill.forTopic(PracticeTopic.geometry)) {
        expect(gen.supports(skill), isTrue, reason: '${skill.id} has no template');
      }
    });
  });
}
