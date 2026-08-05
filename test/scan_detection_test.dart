import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matheasy/features/scan/application/scan_image_codec.dart';
import 'package:matheasy/features/scan/domain/detected_region.dart';
import 'package:matheasy/features/scan/domain/math_text_scorer.dart';

DetectedTextBlock _block(String text, Rect bounds) =>
    DetectedTextBlock(text: text, bounds: bounds);

void main() {
  group('mathScoreFor', () {
    test('an equation scores above the threshold', () {
      for (final equation in [
        '2x + 5 = 13',
        'x^2 - 4x + 3 = 0',
        '3/4 + 1/2',
        '∫ x dx',
        '5 + 7',
      ]) {
        expect(
          mathScoreFor(equation),
          greaterThanOrEqualTo(DetectedRegion.kMathScoreThreshold),
          reason: '"$equation" should read as maths',
        );
      }
    });

    test('prose scores below the threshold', () {
      for (final prose in [
        'Chapter four: introduction to algebra',
        'Answer all questions in the spaces provided',
        'Name',
        'Mathematics Department Worksheet',
      ]) {
        expect(
          mathScoreFor(prose),
          lessThan(DetectedRegion.kMathScoreThreshold),
          reason: '"$prose" should not read as maths',
        );
      }
    });

    test('a wordy sentence with one number is still prose', () {
      // The failure this guards: scoring on digits alone would let any
      // paragraph containing a page number pull the crop box across the page.
      expect(
        mathScoreFor('Turn to page 42 and complete the following exercises'),
        lessThan(DetectedRegion.kMathScoreThreshold),
      );
    });

    test('empty and whitespace-only text score zero', () {
      expect(mathScoreFor(''), 0);
      expect(mathScoreFor('   \n '), 0);
    });

    test('the score never leaves 0..1', () {
      for (final text in ['= = = ∫∫∫ 111 +++', 'aaaaaaaaaaaaaaaaaaaa']) {
        final score = mathScoreFor(text);
        expect(score, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('regionFromBlocks', () {
    const frame = Size(1000, 2000);

    test('no blocks means nothing to frame', () {
      expect(regionFromBlocks(const [], frame), DetectedRegion.none);
      expect(regionFromBlocks([_block('x=1', Rect.zero)], Size.zero),
          DetectedRegion.none);
    });

    test('normalises the union of the maths blocks', () {
      final region = regionFromBlocks(
        [
          _block('2x + 5 = 13', const Rect.fromLTRB(100, 200, 500, 300)),
          _block('x = 4', const Rect.fromLTRB(100, 400, 300, 500)),
        ],
        frame,
      );
      expect(region.bounds.left, closeTo(0.1, 1e-9));
      expect(region.bounds.top, closeTo(0.1, 1e-9));
      expect(region.bounds.right, closeTo(0.5, 1e-9));
      expect(region.bounds.bottom, closeTo(0.25, 1e-9));
      expect(region.looksLikeMath, isTrue);
    });

    test('prose on the page does not stretch the box', () {
      // The worksheet case: a header at the top and a page number at the
      // bottom would otherwise make "the maths" mean "the whole sheet".
      final region = regionFromBlocks(
        [
          _block('Algebra Worksheet Three', const Rect.fromLTRB(0, 0, 900, 60)),
          _block('2x + 5 = 13', const Rect.fromLTRB(100, 900, 500, 1000)),
          _block('Page seventeen', const Rect.fromLTRB(400, 1900, 700, 1960)),
        ],
        frame,
      );
      expect(region.bounds.top, closeTo(0.45, 1e-9));
      expect(region.bounds.bottom, closeTo(0.5, 1e-9));
      // blockCount still reports the WHOLE page — it describes the document,
      // not the crop.
      expect(region.blockCount, 3);
    });

    test('falls back to all text when nothing scores as maths', () {
      final region = regionFromBlocks(
        [_block('Describe the shape below', const Rect.fromLTRB(0, 0, 500, 100))],
        frame,
      );
      expect(region.isNotEmpty, isTrue);
      // Honest about what it is: framed, but not claimed to be maths.
      expect(region.looksLikeMath, isFalse);
    });

    test('the score is the best block, not the average', () {
      final region = regionFromBlocks(
        [
          _block('2x + 5 = 13', const Rect.fromLTRB(0, 0, 100, 50)),
          _block('7 = 3 + 4', const Rect.fromLTRB(0, 60, 100, 110)),
        ],
        frame,
      );
      expect(
        region.mathScore,
        mathScoreFor('2x + 5 = 13') > mathScoreFor('7 = 3 + 4')
            ? mathScoreFor('2x + 5 = 13')
            : mathScoreFor('7 = 3 + 4'),
      );
    });

    test('two horizontal clusters read as a figure beside the problem', () {
      final region = regionFromBlocks(
        [
          _block('x = 3', const Rect.fromLTRB(0, 0, 100, 50)),
          _block('y = 4', const Rect.fromLTRB(10, 60, 110, 110)),
          _block('5 cm', const Rect.fromLTRB(800, 0, 900, 50)),
        ],
        frame,
      );
      expect(region.hasDiagram, isTrue);
    });
  });

  group('cropRectFor', () {
    test('an empty region crops nothing away', () {
      expect(cropRectFor(DetectedRegion.none),
          const Rect.fromLTRB(0, 0, 1, 1));
    });

    test('pads around the detected bounds', () {
      const region = DetectedRegion(
        bounds: Rect.fromLTRB(0.3, 0.4, 0.7, 0.8),
        blockCount: 1,
        mathScore: 0.8,
      );
      final rect = cropRectFor(region);
      expect(rect.left, lessThan(0.3));
      expect(rect.top, lessThan(0.4));
      expect(rect.right, greaterThan(0.7));
      expect(rect.bottom, greaterThan(0.8));
    });

    test('a diagram gets a wider margin than plain text', () {
      const bounds = Rect.fromLTRB(0.3, 0.3, 0.7, 0.7);
      final plain = cropRectFor(const DetectedRegion(
          bounds: bounds, blockCount: 1, mathScore: 0.8));
      final figure = cropRectFor(const DetectedRegion(
          bounds: bounds, blockCount: 4, mathScore: 0.8, hasDiagram: true));
      expect(figure.width, greaterThan(plain.width));
      expect(figure.height, greaterThan(plain.height));
    });

    test('a tiny detection is widened rather than trusted', () {
      const region = DetectedRegion(
        bounds: Rect.fromLTRB(0.49, 0.49, 0.51, 0.51),
        blockCount: 1,
        mathScore: 0.9,
      );
      final rect = cropRectFor(region);
      expect(rect.width, greaterThanOrEqualTo(0.25));
      expect(rect.height, greaterThanOrEqualTo(0.25));
    });

    test('never leaves the frame', () {
      const region = DetectedRegion(
        bounds: Rect.fromLTRB(0, 0, 1, 1),
        blockCount: 1,
        mathScore: 0.9,
      );
      final rect = cropRectFor(region);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(1));
      expect(rect.bottom, lessThanOrEqualTo(1));
    });
  });

  group('rotateScanJpeg', () {
    test('turns the image a quarter clockwise at full resolution', () {
      // A wide white image with a black LEFT half: after a clockwise quarter
      // turn it must be tall with a black TOP half — proving both the turn and
      // its direction, not just the swapped dimensions.
      final image = img.Image(width: 400, height: 200);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      img.fillRect(image,
          x1: 0, y1: 0, x2: 199, y2: 199, color: img.ColorRgb8(0, 0, 0));
      final source = Uint8List.fromList(img.encodeJpg(image));

      final rotated = img.decodeImage(rotateScanJpeg(source))!;
      expect(rotated.width, 200);
      expect(rotated.height, 400);
      expect(rotated.getPixel(100, 100).r, lessThan(40)); // top: was left
      expect(rotated.getPixel(100, 300).r, greaterThan(200)); // bottom: white
    });

    test('undecodable bytes come back untouched rather than throwing', () {
      final junk = Uint8List.fromList(List.filled(64, 7));
      expect(rotateScanJpeg(junk), junk);
    });
  });
}
