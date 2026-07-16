// Geometry Visual Learning — automatic detection.
//
// The keyword classifier that decides whether a problem is geometry (spec
// requirement 1). Pure and offline.

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/geometry_detector.dart';

void main() {
  group('GeometryDetector.isGeometry', () {
    test('hits every spec keyword', () {
      expect(GeometryDetector.isGeometry('Find the missing angle in the triangle'),
          isTrue);
      expect(GeometryDetector.isGeometry('two angles are 60 and 40'), isTrue);
      expect(GeometryDetector.isGeometry('the circle has radius 5'), isTrue);
      expect(
          GeometryDetector.isGeometry('parallel lines cut by a transversal'),
          isTrue);
      expect(GeometryDetector.isGeometry('a regular polygon with 5 sides'),
          isTrue);
      expect(GeometryDetector.isGeometry('a geometry problem'), isTrue);
    });

    test('is case-insensitive', () {
      expect(GeometryDetector.isGeometry('TRIANGLE ABC'), isTrue);
      expect(GeometryDetector.isGeometry('Angle X'), isTrue);
    });

    test('matches on word boundaries only (no false hits inside words)', () {
      // "angle" must not fire inside "strangle"/"mangle"/LaTeX \rangle.
      expect(GeometryDetector.isGeometry('do not strangle the variable'),
          isFalse);
      expect(GeometryDetector.isGeometry(r'\langle v, w \rangle'), isFalse);
      // "triangle" must not fire inside "rectriangleization" nonsense words.
      expect(GeometryDetector.isGeometry('untriangleable'), isFalse);
    });

    test('is false for non-geometry algebra/arithmetic', () {
      expect(GeometryDetector.isGeometry('2x + 5 = 13'), isFalse);
      expect(GeometryDetector.isGeometry('integrate x^2 dx'), isFalse);
      expect(GeometryDetector.isGeometry(''), isFalse);
      expect(GeometryDetector.isGeometry(null), isFalse);
    });

    test('reports the matched keywords', () {
      final hits =
          GeometryDetector.matchedKeywords('the triangle and the circle');
      expect(hits, containsAll(<String>['triangle', 'circle']));
    });
  });
}
