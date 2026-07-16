import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/brand/matheasy_app_icon.dart';
import 'package:matheasy/core/brand/matheasy_mark.dart';
import 'package:matheasy/core/theme/app_colors.dart';

/// The mark is the identity. Before this suite nothing pinned its geometry at
/// all — the R8→M swap had no test to break, and `lib/core/brand/` had zero
/// coverage. These assertions are cheap and catch the ways a CustomPainter
/// silently goes wrong: an open path, a drifted aspect, a scale that distorts.
void main() {
  group('MatheasyMarkPainter geometry', () {
    // Measured off the logo artwork. If this moves, the mark no longer matches
    // the logo it was derived from. See docs/matheasy-brand-system.md §4.
    const expectedAspect = 1.424; // sheared width : height

    test('the path is non-empty and closed', () {
      final b = MatheasyMarkPainter.buildPath().getBounds();
      expect(b.isEmpty, isFalse);
      // A closed fill contains its own interior; an open/degenerate path would
      // not. Sample a point inside the left stem.
      expect(MatheasyMarkPainter.buildPath().contains(const Offset(12, 70)),
          isTrue);
    });

    test('the M fills the viewBox width and is height-centred in it', () {
      final b = MatheasyMarkPainter.buildPath().getBounds();
      expect(b.left, closeTo(0, 0.5));
      expect(b.right, closeTo(MatheasyMarkPainter.viewBox, 0.5));
      expect(
        b.top,
        closeTo(MatheasyMarkPainter.viewBox - b.bottom, 0.5),
        reason: 'the M must sit optically centred in the square mark box',
      );
    });

    test('keeps the italic aspect measured on the artwork', () {
      final b = MatheasyMarkPainter.buildPath().getBounds();
      expect(
        b.width / b.height,
        closeTo(expectedAspect, 0.02),
        reason: 'the M is a bold italic letterform; its aspect follows the '
            '21° slant measured on the logo',
      );
    });

    test('the notch and the V descend to their measured depths', () {
      final b = MatheasyMarkPainter.buildPath().getBounds();
      // The inner V vertex is the lowest point of the middle of the M. Walk the
      // horizontal centre band and find where the fill stops.
      final cx = b.center.dx;
      var vDepth = b.top;
      for (var y = b.top; y <= b.bottom; y += 0.25) {
        if (MatheasyMarkPainter.buildPath().contains(Offset(cx, y))) vDepth = y;
      }
      // Measured on the artwork at 76% of cap height; the rounded join softens
      // it a little, so allow a few points.
      final pct = (vDepth - b.top) / b.height * 100;
      expect(
        pct,
        inInclusiveRange(66, 84),
        reason: 'the inner V of the M descends to ~76% of cap height '
            '(measured); got ${pct.toStringAsFixed(1)}%',
      );
    });

    test('repaints only when the color changes', () {
      const a = MatheasyMarkPainter(color: AppColors.white);
      const b = MatheasyMarkPainter(color: AppColors.white);
      const c = MatheasyMarkPainter(color: AppColors.primaryAction);
      expect(a.shouldRepaint(b), isFalse);
      expect(a.shouldRepaint(c), isTrue);
    });
  });

  group('MatheasyMark widget', () {
    testWidgets('renders at the requested size', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          // Centred so the mark is free to size itself rather than being
          // forced to the surface's tight constraints.
          child: Center(child: MatheasyMark(size: 64)),
        ),
      );
      expect(tester.getSize(find.byType(MatheasyMark)), const Size(64, 64));
    });

    testWidgets('paints without throwing from 16px to 1024px', (tester) async {
      // The tab bar renders at 24 and the App Store icon at 1024.
      for (final size in <double>[16, 24, 48, 120, 1024]) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(child: MatheasyMark(size: size)),
          ),
        );
        expect(tester.takeException(), isNull, reason: 'failed at ${size}px');
      }
    });

    testWidgets('is hidden from semantics unless given a label', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MatheasyMark(size: 44),
        ),
      );
      expect(find.byType(ExcludeSemantics), findsOneWidget);
    });

    testWidgets('exposes a label when one is given', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MatheasyMark(size: 44, semanticLabel: 'Matheasy'),
        ),
      );
      expect(
        tester.getSemantics(find.byType(MatheasyMark)).label,
        'Matheasy',
      );
      handle.dispose();
    });
  });

  group('MatheasyAppIcon', () {
    testWidgets('the tile is flat identity emerald — never a gradient',
        (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: MatheasyAppIcon(size: 128),
        ),
      );
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(MatheasyAppIcon),
              matching: find.byType(Container),
            )
            .first,
      );
      final deco = container.decoration! as BoxDecoration;
      // The logo's tile measures #06AD62 → #06AB5F corner to corner — an
      // imperceptible shift. The brand does not gradient its emerald.
      expect(deco.gradient, isNull);
      expect(deco.color, AppColors.primary);
    });

    test('exposes the tile constants the icon generator must reuse', () {
      // tool/generate_app_icons.dart used to hardcode 0.225 / 0.56 against these
      // 0.2237 / 0.58, so the shipped raster and the in-app icon drifted while
      // the docstring promised they could not.
      expect(MatheasyAppIcon.radiusFraction, closeTo(0.2237, 0.0001));
      expect(MatheasyAppIcon.markFraction, closeTo(0.58, 0.0001));
    });
  });
}
