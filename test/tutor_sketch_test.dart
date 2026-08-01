import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/domain/visual_models.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/concept_painter.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_sketch_view.dart';

/// Spec Part 9 — the drawing beside an explanation.
///
/// The drawing exists to make a verified fact visible, so the property that
/// matters is that it *ends* on the derived numbers. It may animate on the way
/// there; it may never settle anywhere else.
VisualConcept _sketch(
  VisualConceptKind kind,
  Map<String, double> params,
) =>
    VisualConcept(kind: kind, caption: 'a drawing', params: params);

void main() {
  group('sketchAtProgress', () {
    test('lands exactly on the derived numbers', () {
      const params = {'a': 1.0, 'b': 8.0, 'c': 4.0, 'from': 0.0, 'to': 2.0};
      for (final kind in VisualConceptKind.values) {
        final sketch = _sketch(kind, params);
        expect(sketchAtProgress(sketch, 1).params, params,
            reason: '$kind must finish on the derived values');
        // Overshoot and rewind are clamped, not extrapolated.
        expect(sketchAtProgress(sketch, 1.4).params, params);
      }
    });

    // "Integrals — animate area": the shading sweeps out from the lower bound.
    test('grows the shaded region from its lower bound', () {
      final sketch = _sketch(
        VisualConceptKind.areaUnderCurve,
        {'a': 1, 'b': 0, 'c': 0, 'from': 1, 'to': 5},
      );
      expect(sketchAtProgress(sketch, 0).param('to'), 1);
      expect(sketchAtProgress(sketch, 0.5).param('to'), 3);
      expect(sketchAtProgress(sketch, 1).param('to'), 5);
      // The window never moves, or the curve would rescale under the sweep.
      expect(sketchAtProgress(sketch, 0.5).param('from'), 1);
      expect(sketchAtProgress(sketch, 0.5).param('a'), 1);
    });

    test('fills the fraction bar a part at a time', () {
      final sketch = _sketch(
        VisualConceptKind.fractionBar,
        {'numerator': 3, 'denominator': 4},
      );
      expect(sketchAtProgress(sketch, 0).param('numerator'), 0);
      expect(sketchAtProgress(sketch, 0.5).param('numerator'), 1.5);
      // The bar it fills never changes size mid-fill.
      expect(sketchAtProgress(sketch, 0.5).param('denominator'), 4);
    });

    test('opens the angle from zero', () {
      final sketch = _sketch(VisualConceptKind.unitCircle, {'angleDegrees': 60});
      expect(sketchAtProgress(sketch, 0).param('angleDegrees'), 0);
      expect(sketchAtProgress(sketch, 0.5).param('angleDegrees'), 30);
    });

    // A half-drawn parabola is not a parabola part-way through happening — it
    // is a different, shorter curve, which would say something untrue.
    test('leaves a curve alone, because a partial one would lie', () {
      final line = _sketch(
        VisualConceptKind.linearGraph,
        {'slope': 2, 'intercept': 3, 'xMin': -5, 'xMax': 5},
      );
      expect(sketchAtProgress(line, 0.3).params, line.params);

      final parabola = _sketch(
        VisualConceptKind.parabolaGraph,
        {'a': 1, 'b': 8, 'c': 4},
      );
      expect(sketchAtProgress(parabola, 0.3).params, parabola.params);
    });

    test('keeps the caption and labels through the animation', () {
      const sketch = VisualConcept(
        kind: VisualConceptKind.unitCircle,
        caption: 'thirty degrees',
        params: {'angleDegrees': 30},
        labels: {'angle': '30°'},
      );
      final mid = sketchAtProgress(sketch, 0.5);
      expect(mid.caption, 'thirty degrees');
      expect(mid.labels['angle'], '30°');
    });
  });

  group('TutorSketchView', () {
    Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(body: SizedBox(width: 300, child: child)),
          ),
        );

    VisualConcept painted(WidgetTester tester) =>
        (tester.widget<CustomPaint>(find.byType(CustomPaint).last).painter
                as ConceptPainter)
            .concept;

    testWidgets('draws itself, then settles on the derived numbers',
        (tester) async {
      await tester.pumpWidget(host(TutorSketchView(_sketch(
        VisualConceptKind.fractionBar,
        {'numerator': 4, 'denominator': 4},
      ))));

      await tester.pump();
      expect(painted(tester).param('numerator'), 0, reason: 'starts empty');
      await tester.pump(const Duration(milliseconds: 300));
      final mid = painted(tester).param('numerator');
      expect(mid, greaterThan(0));
      expect(mid, lessThan(4), reason: 'still filling');
      await tester.pumpAndSettle();
      expect(painted(tester).param('numerator'), 4);
    });

    testWidgets('shows the finished drawing at once when motion is reduced',
        (tester) async {
      await tester.pumpWidget(host(
        TutorSketchView(_sketch(
          VisualConceptKind.fractionBar,
          {'numerator': 4, 'denominator': 4},
        )),
        reduceMotion: true,
      ));
      await tester.pump();
      expect(painted(tester).param('numerator'), 4);
    });

    // The canvas announces the caption instead of leaking a tree of shapes.
    testWidgets('reads as one image to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(TutorSketchView(_sketch(
        VisualConceptKind.numberLine,
        {'value': 4, 'min': 0, 'max': 7},
      ))));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('a drawing'), findsOneWidget);
      handle.dispose();
    });
  });
}
