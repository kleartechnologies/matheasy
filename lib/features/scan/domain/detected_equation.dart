import 'package:flutter/foundation.dart';

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
  });

  final String latex;

  /// Recognition confidence in the range 0–1.
  final double confidence;

  final ScanSource source;
  final EquationKind kind;

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
  }) {
    return DetectedEquation(
      latex: latex ?? this.latex,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      kind: kind ?? this.kind,
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
