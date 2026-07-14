// Scanner V2 tests — the recognize → confirm state machine, the OpenAI-Vision
// response mapping (topic → kind), the offline mock recognizer, and the
// cropped-image JPEG codec. Camera + crop UI are native and covered by the
// graceful-fallback widget test in widget_test.dart; here we exercise the pure
// logic the pipeline depends on.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/features/scan/application/functions_scanner_service.dart';
import 'package:matheasy/features/scan/application/scan_image_codec.dart';
import 'package:matheasy/features/scan/application/scanner_controller.dart';
import 'package:matheasy/features/scan/application/scanner_service.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/scan/domain/scan_state.dart';

/// A configurable [ScannerService] fake: returns [result] or throws [error],
/// gated on [gate] so tests can observe the in-flight [ScanRecognizing] state.
class _FakeScannerService implements ScannerService {
  _FakeScannerService({this.result, this.error, this.gate});

  final DetectedEquation? result;
  final Object? error;
  final Future<void>? gate;

  @override
  Future<DetectedEquation> recognize(
    ScanSource source, {
    Uint8List? imageBytes,
    String? manualLatex,
  }) async {
    if (gate != null) await gate;
    if (error != null) throw error!;
    return result!;
  }
}

Uint8List _bytes() => Uint8List.fromList(List<int>.generate(16, (i) => i));

const _equation = DetectedEquation(
  latex: r'2x + 5 = 13',
  confidence: 0.98,
  source: ScanSource.camera,
  kind: EquationKind.linear,
);

void main() {
  group('MockScannerService', () {
    test('manual entry wraps typed latex and infers the kind', () async {
      const service = MockScannerService();
      final eq = await service.recognize(ScanSource.manual,
          manualLatex: r'x^2 - 9 = 0');
      expect(eq.latex, r'x^2 - 9 = 0');
      expect(eq.source, ScanSource.manual);
      expect(eq.kind, EquationKind.quadratic);
      expect(eq.confidence, 1);
    });

    test('camera / gallery return source-specific samples', () async {
      const service = MockScannerService();
      final camera = await service.recognize(ScanSource.camera,
          imageBytes: _bytes());
      expect(camera.kind, EquationKind.linear);
      final gallery = await service.recognize(ScanSource.gallery,
          imageBytes: _bytes());
      expect(gallery.kind, EquationKind.quadratic);
    });
  });

  group('FunctionsScannerService (OpenAI Vision mapping)', () {
    test('prefers the backend topic over LaTeX inference', () async {
      final service = FunctionsScannerService((name, data) async {
        expect(name, 'recognizeEquation');
        expect(data['imageBase64'], isNotEmpty);
        expect(data['mimeType'], 'image/jpeg');
        // LaTeX alone would infer linear; the topic says quadratic.
        return {'latex': '2x = 4', 'confidence': 0.9, 'topic': 'quadratic'};
      });
      final eq = await service.recognize(ScanSource.camera, imageBytes: _bytes());
      expect(eq.kind, EquationKind.quadratic);
      expect(eq.confidence, closeTo(0.9, 1e-9));
    });

    test('preserves a FULL multi-line problem transcription (no truncation)',
        () async {
      // Regression: OCR used to drop everything but one equation. The client must
      // pass the whole multi-line problem — given + question + all parts — through
      // to DetectedEquation.latex verbatim, so the solver receives full context.
      const fullProblem =
          r"\text{f(x) is differentiable} \\ x \cdot f'(x) + f(x) = "
          r"\frac{d}{dx}(x^4 - x) \\ f'(2) = 10 \\ \text{what is } f(-1)?";
      final service = FunctionsScannerService((name, data) async =>
          {'latex': fullProblem, 'confidence': 0.9, 'topic': 'calculus'});
      final eq =
          await service.recognize(ScanSource.camera, imageBytes: _bytes());
      expect(eq.latex, fullProblem); // every line intact
      expect(eq.latex, contains("f'(2) = 10")); // the given
      expect(eq.latex, contains('f(-1)')); // the question
      expect(r'\\'.allMatches(eq.latex).length, 3); // 4 lines → 3 row breaks
    });

    test('falls back to LaTeX inference when topic is unknown/absent', () async {
      final service = FunctionsScannerService((name, data) async =>
          {'latex': r'\frac{1}{2} + \frac{1}{3}', 'confidence': 0.8});
      final eq = await service.recognize(ScanSource.gallery, imageBytes: _bytes());
      expect(eq.kind, EquationKind.fraction);
    });

    test('throws a typed BackendException when no math is found', () {
      final service =
          FunctionsScannerService((name, data) async => {'latex': ''});
      expect(
        () => service.recognize(ScanSource.camera, imageBytes: _bytes()),
        throwsA(isA<BackendException>()
            .having((e) => e.code, 'code', 'not-found')),
      );
    });

    test('kindFromTopic maps the full Vision taxonomy', () {
      expect(FunctionsScannerService.kindFromTopic('linear_equation'),
          EquationKind.linear);
      expect(FunctionsScannerService.kindFromTopic('simultaneous'),
          EquationKind.linear);
      expect(FunctionsScannerService.kindFromTopic('quadratic'),
          EquationKind.quadratic);
      expect(FunctionsScannerService.kindFromTopic('fraction'),
          EquationKind.fraction);
      expect(FunctionsScannerService.kindFromTopic('trigonometry'),
          EquationKind.trigonometry);
      expect(FunctionsScannerService.kindFromTopic('calculus'),
          EquationKind.expression);
      expect(FunctionsScannerService.kindFromTopic('mystery'), isNull);
      expect(FunctionsScannerService.kindFromTopic(null), isNull);
    });
  });

  group('ScannerController', () {
    ProviderContainer containerWith(_FakeScannerService service) {
      final container = ProviderContainer(
        overrides: [scannerServiceProvider.overrideWithValue(service)],
      );
      addTearDown(container.dispose);
      // Keep the auto-dispose controller alive for the test.
      container.listen(scannerControllerProvider, (_, _) {});
      return container;
    }

    test('recognize success moves Idle → Captured', () async {
      final container =
          containerWith(_FakeScannerService(result: _equation));
      final notifier = container.read(scannerControllerProvider.notifier);
      expect(container.read(scannerControllerProvider), isA<ScanIdle>());

      await notifier.recognize(ScanSource.camera, imageBytes: _bytes());
      final state = container.read(scannerControllerProvider);
      expect(state, isA<ScanCaptured>());
      expect((state as ScanCaptured).equation, _equation);
    });

    test('an unreadable image surfaces a couldnt-recognize ScanError (§9)',
        () async {
      final container = containerWith(_FakeScannerService(
        error: const BackendException('No math detected.', code: 'not-found'),
      ));
      final notifier = container.read(scannerControllerProvider.notifier);
      await notifier.recognize(ScanSource.gallery, imageBytes: _bytes());
      final state = container.read(scannerControllerProvider);
      expect(state, isA<ScanError>());
      expect((state as ScanError).message, 'No math detected.');
      expect(state.kind, ScanErrorKind.couldntRecognize);
    });

    test('a dropped connection surfaces an OFFLINE ScanError (§9)', () async {
      final container = containerWith(_FakeScannerService(
        error: const BackendException('unavailable', code: 'unavailable'),
      ));
      final notifier = container.read(scannerControllerProvider.notifier);
      await notifier.recognize(ScanSource.camera, imageBytes: _bytes());
      final state = container.read(scannerControllerProvider);
      expect(state, isA<ScanError>());
      expect((state as ScanError).kind, ScanErrorKind.offline);
    });

    test('unexpected errors surface a generic ScanError', () async {
      final container =
          containerWith(_FakeScannerService(error: StateError('boom')));
      final notifier = container.read(scannerControllerProvider.notifier);
      await notifier.recognize(ScanSource.camera, imageBytes: _bytes());
      final state = container.read(scannerControllerProvider);
      expect(state, isA<ScanError>());
      expect((state as ScanError).kind, ScanErrorKind.generic);
    });

    test('a server quota rejection surfaces ScanQuotaExceeded (paywall signal)',
        () async {
      final container = containerWith(_FakeScannerService(
        error: const BackendException('Free-tier limit reached.',
            code: 'resource-exhausted'),
      ));
      final notifier = container.read(scannerControllerProvider.notifier);
      await notifier.recognize(ScanSource.gallery, imageBytes: _bytes());
      expect(
          container.read(scannerControllerProvider), isA<ScanQuotaExceeded>());
    });

    test('a second recognize is ignored while one is in flight', () async {
      final gate = Completer<void>();
      final container = containerWith(
        _FakeScannerService(result: _equation, gate: gate.future),
      );
      final notifier = container.read(scannerControllerProvider.notifier);

      final first = notifier.recognize(ScanSource.camera, imageBytes: _bytes());
      expect(container.read(scannerControllerProvider), isA<ScanRecognizing>());

      // Ignored — still recognizing, not restarted.
      final second = notifier.recognize(ScanSource.camera, imageBytes: _bytes());
      await second;
      expect(container.read(scannerControllerProvider), isA<ScanRecognizing>());

      gate.complete();
      await first;
      expect(container.read(scannerControllerProvider), isA<ScanCaptured>());
    });

    test('confirm from Captured hands off to Complete; retake resets to Idle',
        () async {
      final container =
          containerWith(_FakeScannerService(result: _equation));
      final notifier = container.read(scannerControllerProvider.notifier);
      await notifier.recognize(ScanSource.camera, imageBytes: _bytes());

      notifier.confirm();
      final complete = container.read(scannerControllerProvider);
      expect(complete, isA<ScanComplete>());
      expect((complete as ScanComplete).equation, _equation);

      notifier.retake();
      expect(container.read(scannerControllerProvider), isA<ScanIdle>());
    });

    test('confirm is a no-op when nothing is captured', () async {
      final container =
          containerWith(_FakeScannerService(result: _equation));
      final notifier = container.read(scannerControllerProvider.notifier);
      notifier.confirm();
      expect(container.read(scannerControllerProvider), isA<ScanIdle>());
    });

    test('applyEdit rewrites the latex, KEEPS the source, and sets 100% conf',
        () async {
      final container = containerWith(_FakeScannerService(result: _equation));
      final notifier = container.read(scannerControllerProvider.notifier);
      await notifier.recognize(ScanSource.camera, imageBytes: _bytes());

      notifier.applyEdit(r'x^2 - 9 = 0');
      final state = container.read(scannerControllerProvider) as ScanCaptured;
      expect(state.equation.latex, r'x^2 - 9 = 0');
      // Source preserved → re-solving reuses the already-charged scan (no
      // double-metering); confidence is 100% (the human verified it); kind
      // re-inferred from the corrected LaTeX.
      expect(state.equation.source, ScanSource.camera);
      expect(state.equation.confidence, 1);
      expect(state.equation.kind, EquationKind.quadratic);
    });

    test('applyEdit is ignored off Captured or with empty latex', () async {
      final container = containerWith(_FakeScannerService(result: _equation));
      final notifier = container.read(scannerControllerProvider.notifier);

      notifier.applyEdit('x = 1'); // still Idle → ignored
      expect(container.read(scannerControllerProvider), isA<ScanIdle>());

      await notifier.recognize(ScanSource.camera, imageBytes: _bytes());
      notifier.applyEdit('   '); // empty → capture unchanged
      final state = container.read(scannerControllerProvider) as ScanCaptured;
      expect(state.equation.latex, _equation.latex);
    });
  });

  group('encodeScanJpeg', () {
    test('re-encodes to JPEG (SOI marker) regardless of input format', () {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 8, height: 8)));
      final out = encodeScanJpeg(png);
      expect(out.length, greaterThan(2));
      expect(out[0], 0xFF); // JPEG start-of-image
      expect(out[1], 0xD8);
    });

    test('downscales images larger than the cap on their longest edge', () {
      final big =
          Uint8List.fromList(img.encodePng(img.Image(width: 3000, height: 1000)));
      final out = encodeScanJpeg(big);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, kScanMaxSide);
      expect(decoded.height, lessThanOrEqualTo(kScanMaxSide));
    });

    test('returns the input unchanged when it cannot be decoded', () {
      final junk = Uint8List.fromList([1, 2, 3, 4]);
      expect(encodeScanJpeg(junk), junk);
    });

    test('isJpegBytes detects the SOI marker', () {
      final jpeg = encodeScanJpeg(
          Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4))));
      expect(isJpegBytes(jpeg), isTrue);
      expect(isJpegBytes(Uint8List.fromList([0x89, 0x50])), isFalse); // PNG
      expect(isJpegBytes(Uint8List.fromList([0xFF])), isFalse); // too short
    });
  });
}
