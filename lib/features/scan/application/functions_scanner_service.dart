import 'package:flutter/foundation.dart';

import '../../../core/backend/functions_client.dart';
import '../domain/detected_equation.dart';
import '../domain/scan_anchor.dart';
import '../domain/scan_source.dart';
import 'scan_image_codec.dart';
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

    // Base64 in an isolate, never on the UI thread: a ~900KB JPEG becomes a
    // ~1.2MB string, and building that synchronously drops frames exactly while
    // the user is watching the capture for a sign of life.
    final imageBase64 = await compute(encodeScanBase64, imageBytes);

    final json = await _call('recognizeEquation', {
      'imageBase64': imageBase64,
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
    final geometry = json['geometry'];
    final ocr = json['ocr'];
    return DetectedEquation(
      latex: latex,
      confidence: confidence is num ? confidence.toDouble().clamp(0.0, 1.0) : 0.9,
      source: source,
      kind: kindFromTopic(topic) ?? inferKind(latex),
      // Keep the cropped scan so the result screen can show the figure.
      imageBytes: imageBytes,
      // Structured geometry facts (angle/Pythagoras) the recognizer extracted,
      // used to render the diagram-first player — see GeometryPayloadMapper.
      geometry: geometry is Map
          ? Map<String, dynamic>.from(geometry)
          : null,
      // How the page was read (the transcription pass's draft + its doubts).
      // Absent on an older backend — the tutor context simply omits the block.
      ocr: ocr is Map ? Map<String, dynamic>.from(ocr) : null,
      // WHERE each concept sits on the photo, so the tutor can point at the
      // student's own page instead of reading values out loud. Empty on an
      // older backend, which simply means no overlay.
      anchors: ScanAnchor.listFromJson(json['anchors']),
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
      // The Vision topic is the ONLY geometry signal in the pipeline — the solver
      // is geometry-blind (a geometry problem looks like a linear equation), so we
      // preserve it here to route solved geometry to geometry practice.
      // KNOWN LIMITATION: this lights up SCANNED geometry only. The math-keyboard
      // (typed) path carries no Vision topic, so typed geometry stays classified
      // as its LaTeX shape (algebra) — a deliberate scope boundary, not a bug.
      case 'geometry':
        return EquationKind.geometry;
      case 'arithmetic':
      case 'percentage':
      case 'ratio':
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
