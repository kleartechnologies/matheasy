import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../domain/detected_equation.dart';
import '../domain/scan_source.dart';
import 'functions_scanner_service.dart';

/// Recognizes math problems from the camera / gallery / manual input.
///
/// This is the seam Stage 5 plugs into: swap [MockScannerService] for a real
/// implementation (Mathpix + camera frames, or an LLM vision fallback) by
/// overriding [scannerServiceProvider]. Nothing else in the scanner changes —
/// the controller and UI depend only on this interface and [DetectedEquation].
abstract interface class ScannerService {
  /// A live stream of candidate detections from the camera preview. Emits
  /// `null` while nothing is recognized, then the best current candidate.
  Stream<DetectedEquation?> liveDetections();

  /// Recognizes a single problem from the given [source].
  ///
  /// [imageBytes] carries a captured/picked photo for OCR (camera + gallery);
  /// [manualLatex] carries a typed problem (manual entry, no OCR). The mock
  /// ignores both and returns a sample.
  Future<DetectedEquation> recognize(
    ScanSource source, {
    Uint8List? imageBytes,
    String? manualLatex,
  });
}

/// Timings for the mock experience — also referenced by the UI/tests so the
/// simulated pace stays consistent.
class ScannerTimings {
  const ScannerTimings._();
  static const Duration liveDetectDelay = Duration(milliseconds: 1600);
  static const Duration recognizeDelay = Duration(milliseconds: 400);
  static const Duration processing = Duration(milliseconds: 2400);
}

/// A deterministic, offline mock recognizer used through Stage 4.
class MockScannerService implements ScannerService {
  const MockScannerService();

  static const List<(String, double, EquationKind)> _samples = [
    (r'2x + 5 = 13', 0.99, EquationKind.linear),
    (r'x^2 + 5x + 6 = 0', 0.97, EquationKind.quadratic),
    (r'\frac{3}{4} + \frac{1}{2}', 0.96, EquationKind.fraction),
  ];

  DetectedEquation _sample(int index, ScanSource source) {
    final (latex, confidence, kind) = _samples[index % _samples.length];
    return DetectedEquation(
      latex: latex,
      confidence: confidence,
      source: source,
      kind: kind,
    );
  }

  @override
  Stream<DetectedEquation?> liveDetections() async* {
    yield null;
    await Future<void>.delayed(ScannerTimings.liveDetectDelay);
    yield _sample(0, ScanSource.camera);
  }

  @override
  Future<DetectedEquation> recognize(
    ScanSource source, {
    Uint8List? imageBytes,
    String? manualLatex,
  }) async {
    await Future<void>.delayed(ScannerTimings.recognizeDelay);
    final index = switch (source) {
      ScanSource.camera => 0,
      ScanSource.gallery => 1,
      ScanSource.manual => 2,
    };
    return _sample(index, source);
  }
}

/// Provides the active [ScannerService]: the real Mathpix-backed recognizer
/// (`recognizeEquation` Cloud Function) for signed-in users with Firebase
/// configured, else the offline mock.
final Provider<ScannerService> scannerServiceProvider =
    Provider<ScannerService>((ref) {
  if (!ref.watch(aiBackendReadyProvider)) return const MockScannerService();
  final functions = ref.watch(firebaseFunctionsProvider);
  return FunctionsScannerService(
    (name, data) => callFunction(functions, name, data),
  );
});
