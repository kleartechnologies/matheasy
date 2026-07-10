import 'dart:convert';
import 'dart:typed_data';

import '../../../core/backend/functions_client.dart';
import '../domain/detected_equation.dart';
import '../domain/scan_source.dart';
import 'scanner_service.dart';

/// Real recognizer — sends a captured/cropped photo to the `recognizeEquation`
/// Cloud Function (OpenAI Vision server-side) and maps the returned LaTeX onto a
/// [DetectedEquation]. Manual entry skips OCR and wraps the typed problem
/// directly.
///
/// Used only for signed-in users with Firebase configured; guests / the
/// unconfigured checkout keep [MockScannerService] (see [scannerServiceProvider]).
class FunctionsScannerService implements ScannerService {
  const FunctionsScannerService(this._call);

  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> data)
      _call;

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
        kind: inferKind(typed),
      );
    }

    if (imageBytes == null || imageBytes.isEmpty) {
      throw const BackendException('No image to recognize.', code: 'invalid-argument');
    }

    final json = await _call('recognizeEquation', {
      'imageBase64': base64Encode(imageBytes),
      'mimeType': 'image/jpeg',
      'source': source.name,
    });

    final latex = json['latex'] is String ? (json['latex'] as String).trim() : '';
    if (latex.isEmpty) {
      throw const BackendException(
        'No math was detected. Try again with the problem centered.',
        code: 'not-found',
      );
    }
    final confidence = json['confidence'];
    final topic = json['topic'] is String ? json['topic'] as String : null;
    return DetectedEquation(
      latex: latex,
      confidence: confidence is num ? confidence.toDouble().clamp(0.0, 1.0) : 0.9,
      source: source,
      kind: kindFromTopic(topic) ?? inferKind(latex),
    );
  }

  /// Maps the Vision model's `topic` string onto a display [EquationKind].
  /// Returns `null` for an unknown/absent topic so the caller can fall back to
  /// [inferKind]. The result screen returns the authoritative type; this is only
  /// the pre-solve caption.
  static EquationKind? kindFromTopic(String? topic) {
    switch (topic) {
      case 'linear_equation':
      case 'simultaneous':
        return EquationKind.linear;
      case 'quadratic':
        return EquationKind.quadratic;
      case 'fraction':
        return EquationKind.fraction;
      case 'trigonometry':
        return EquationKind.trigonometry;
      case 'arithmetic':
      case 'percentage':
      case 'ratio':
      case 'geometry':
      case 'calculus':
      case 'statistics':
      case 'other':
        return EquationKind.expression;
      default:
        return null;
    }
  }

  /// Best-effort classification from the LaTeX, for the pre-solve caption only —
  /// the solver returns the authoritative type.
  static EquationKind inferKind(String latex) {
    final l = latex.toLowerCase();
    if (l.contains('^2') || l.contains('²')) return EquationKind.quadratic;
    if (l.contains(r'\frac') || l.contains('/')) return EquationKind.fraction;
    if (l.contains('sin') || l.contains('cos') || l.contains('tan')) {
      return EquationKind.trigonometry;
    }
    if (l.contains('=')) return EquationKind.linear;
    return EquationKind.expression;
  }
}
