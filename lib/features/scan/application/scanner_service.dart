import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/functions_client.dart';
import '../domain/detected_equation.dart';
import '../domain/scan_source.dart';
import 'functions_scanner_service.dart';

/// Recognizes a math problem from a captured/picked photo or typed input.
///
/// The production implementation ([FunctionsScannerService]) sends the image to
/// the `recognizeEquation` Cloud Function (OpenAI Vision, server-side). The
/// controller and UI depend only on this interface and [DetectedEquation], so
/// the recognizer can be swapped without touching either.
abstract interface class ScannerService {
  /// Recognizes a single problem from the given [source].
  ///
  /// [imageBytes] carries a captured/cropped photo for OCR (camera + gallery);
  /// [manualLatex] carries a typed problem (manual entry, no OCR).
  Future<DetectedEquation> recognize(
    ScanSource source, {
    Uint8List? imageBytes,
    String? manualLatex,
  });
}

/// An offline, deterministic recognizer used only where the real backend can't
/// run: the unconfigured dev checkout, guests (no auth token to meter against),
/// and tests. Signed-in users always get the real [FunctionsScannerService].
class MockScannerService implements ScannerService {
  const MockScannerService();

  static const Duration recognizeDelay = Duration(milliseconds: 400);

  static const List<(String, double, EquationKind)> _samples = [
    (r'2x + 5 = 13', 0.99, EquationKind.linear),
    (r'x^2 + 5x + 6 = 0', 0.97, EquationKind.quadratic),
    (r'\frac{3}{4} + \frac{1}{2}', 0.96, EquationKind.fraction),
  ];

  @override
  Future<DetectedEquation> recognize(
    ScanSource source, {
    Uint8List? imageBytes,
    String? manualLatex,
  }) async {
    final typed = manualLatex?.trim();
    if (typed != null && typed.isNotEmpty) {
      return DetectedEquation(
        latex: typed,
        confidence: 1,
        source: ScanSource.manual,
        kind: FunctionsScannerService.inferKind(typed),
      );
    }
    await Future<void>.delayed(recognizeDelay);
    final index = switch (source) {
      ScanSource.camera => 0,
      ScanSource.gallery => 1,
      ScanSource.manual => 2,
    };
    final (latex, confidence, kind) = _samples[index % _samples.length];
    return DetectedEquation(
      latex: latex,
      confidence: confidence,
      source: source,
      kind: kind,
    );
  }
}

/// Provides the active [ScannerService]: the real OpenAI-Vision recognizer
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
