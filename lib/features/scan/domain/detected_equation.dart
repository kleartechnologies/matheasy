import 'package:flutter/foundation.dart';

import 'scan_anchor.dart';
import 'scan_source.dart';

/// Coarse classification of a detected problem, used for the result caption.
enum EquationKind {
  linear('Linear equation · one unknown'),
  quadratic('Quadratic equation'),
  fraction('Fraction arithmetic'),
  expression('Arithmetic expression'),
  trigonometry('Trigonometry'),
  geometry('Geometry');

  const EquationKind(this.label);

  final String label;
}

/// A recognized math problem.
///
/// [latex] is the recognizer's output in LaTeX (ready for `flutter_math_fork`).
/// STAGE 4 fills this from a mock; Stage 5's Mathpix/vision recognizer produces
/// the same shape, so nothing downstream changes.
@immutable
class DetectedEquation {
  const DetectedEquation({
    required this.latex,
    required this.confidence,
    required this.source,
    required this.kind,
    this.imageBytes,
    this.geometry,
    this.ocr,
    this.anchors = const [],
  });

  final String latex;

  /// Recognition confidence in the range 0–1.
  final double confidence;

  final ScanSource source;
  final EquationKind kind;

  /// The cropped photo this problem was recognized from (camera / gallery),
  /// kept so the result screen can show the student what they scanned —
  /// especially valuable for figure-based problems (geometry) and the
  /// couldn't-verify / tutor states.
  ///
  /// Deliberately TRANSIENT: it is excluded from [toJson]/[fromJson] (history
  /// stays lightweight — no base64 blobs in the sync store) and from
  /// [==]/[hashCode] (so provider/solve caching keys on the problem, not the
  /// pixels). It therefore rides along only for the live scan, not history
  /// re-opens.
  final Uint8List? imageBytes;

  /// Structured geometry facts the recognizer extracted from a solvable angle
  /// or right-triangle problem (the raw `geometry` payload — see
  /// `GeometryPayloadMapper`). Kept as an untyped map so the scan domain stays
  /// decoupled from the result/visual layer; the result screen builds the scene.
  ///
  /// Also TRANSIENT (excluded from JSON + equality) for the same reasons as
  /// [imageBytes] — it's a rendering hint for the live scan, not persisted state.
  final Map<String, dynamic>? geometry;

  /// The scanner's own account of HOW it read the page — the raw `ocr` payload
  /// (`latex`, `confidence`, `uncertain[]`) from the transcription pass.
  ///
  /// Carried so the tutor can be told the read was shaky and exactly which marks
  /// were doubtful: the most common "the app is wrong" is a misread character,
  /// not a bad solve. TRANSIENT for the same reasons as [geometry].
  final Map<String, dynamic>? ocr;

  /// WHERE the marks are on the page, as concepts the tutor can point at (see
  /// [ScanAnchor]). Empty for typed problems, for a history re-open, and
  /// whenever the reader placed nothing.
  ///
  /// TRANSIENT for the same reasons as [imageBytes]: without the photo there is
  /// nothing to draw an overlay on, so persisting the coordinates alone would
  /// only carry dead weight into the sync store.
  final List<ScanAnchor> anchors;

  int get confidencePercent => (confidence * 100).round();

  Map<String, dynamic> toJson() => {
        'latex': latex,
        'confidence': confidence,
        'source': source.name,
        'kind': kind.name,
      };

  factory DetectedEquation.fromJson(Map<String, dynamic> json) =>
      DetectedEquation(
        latex: json['latex'] as String? ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1,
        source: ScanSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => ScanSource.manual,
        ),
        kind: EquationKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => EquationKind.expression,
        ),
      );

  DetectedEquation copyWith({
    String? latex,
    double? confidence,
    ScanSource? source,
    EquationKind? kind,
    Uint8List? imageBytes,
    Map<String, dynamic>? geometry,
    Map<String, dynamic>? ocr,
    List<ScanAnchor>? anchors,
  }) {
    return DetectedEquation(
      latex: latex ?? this.latex,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      kind: kind ?? this.kind,
      // The photo is preserved through an in-place edit (same scan)…
      imageBytes: imageBytes ?? this.imageBytes,
      // …but the structured geometry facts are NOT: an edit corrects a misread,
      // so the recognizer's original extraction no longer applies. It's dropped
      // unless a caller explicitly supplies fresh facts.
      geometry: geometry,
      // Same reasoning: once the student has corrected the text, the original
      // transcription is history — telling the tutor "this was read as …" about
      // a line the student has since rewritten would be actively misleading.
      ocr: ocr,
      // And the same again, with teeth: an edit means at least one mark was
      // read wrong, so every box placed by that read is suspect. Dropping them
      // costs the overlay; keeping them would point at the wrong symbol.
      anchors: anchors ?? const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DetectedEquation &&
      other.latex == latex &&
      other.confidence == confidence &&
      other.source == source &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(latex, confidence, source, kind);

  @override
  String toString() =>
      'DetectedEquation($latex, $confidencePercent%, ${source.name})';
}
