// Scanned-image preservation + display.
//
// The cropped photo now rides along on DetectedEquation so the result screen
// can show what was scanned — but only TRANSIENTLY: it must never bloat history
// (toJson/fromJson) or perturb solve/caching identity (==/hashCode). These
// tests pin both the domain contract and the widget's show/hide behaviour.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/presentation/widgets/result_scan_image.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

// A valid 1x1 transparent PNG — decodable by Image.memory in a widget test.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

DetectedEquation _eq({Uint8List? bytes}) => DetectedEquation(
      latex: r'x^2 = 9',
      confidence: 0.9,
      source: ScanSource.camera,
      kind: EquationKind.geometry,
      imageBytes: bytes,
    );

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('DetectedEquation.imageBytes is transient', () {
    test('is excluded from JSON (history stays lightweight)', () {
      final json = _eq(bytes: _png).toJson();
      expect(json.containsKey('imageBytes'), isFalse);
      expect(DetectedEquation.fromJson(json).imageBytes, isNull);
    });

    test('does not affect equality / hashCode (solve caching keys on problem)',
        () {
      final withImage = _eq(bytes: _png);
      final without = _eq();
      expect(withImage, equals(without));
      expect(withImage.hashCode, without.hashCode);
    });

    test('survives an in-place edit via copyWith', () {
      final edited = _eq(bytes: _png).copyWith(latex: r'x^2 = 16', confidence: 1);
      expect(edited.imageBytes, same(_png));
      expect(edited.latex, r'x^2 = 16');
    });
  });

  group('ResultScanImageSlot', () {
    testWidgets('renders nothing when there is no scan image', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ResultScanImageSlot(imageBytes: null)),
      ));
      expect(find.byType(ResultScanImage), findsNothing);
      expect(find.text('SCANNED PROBLEM'), findsNothing);
    });

    testWidgets('shows the scanned-problem card when bytes are present',
        (tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: ResultScanImageSlot(imageBytes: _png)),
        ));
        await tester.pump();
      });
      expect(find.byType(ResultScanImage), findsOneWidget);
      expect(find.text('SCANNED PROBLEM'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
