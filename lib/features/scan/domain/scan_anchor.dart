import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../../../core/theme/math_semantics.dart';

/// A place on the scanned page that the tutor can point at.
///
/// The scanner's OCR pass reports every mark it read *and where it sits*; the
/// server then turns those marks into concepts a tutor can name — "the angle at
/// B", "the unknown", "the hypotenuse" — deterministically, from the boxes plus
/// the structured geometry facts (`functions/src/proxy/anchors.ts`). This is the
/// client's view of one of those concepts.
///
/// Two properties matter more than anything else here:
///
/// 1. **[rect] is normalized (0–1), not pixels.** The same anchor has to land
///    correctly whether the photo is drawn full-bleed on a tablet or thumbnailed
///    in a chat bubble, and the server never saw either size.
/// 2. **Nothing here is computed from.** An anchor says where something is and
///    what role it plays; it never says what it equals. The verified solver
///    remains the only source of arithmetic — pointing at a number is not the
///    same as trusting a number.
@immutable
class ScanAnchor {
  const ScanAnchor({
    required this.id,
    required this.type,
    required this.label,
    required this.rect,
    this.role = MathRole.aside,
    this.vertex,
    this.confidence = 0.5,
  });

  /// Stable, human-readable, unique within one scan: `angle_B`, `unknown_x`.
  /// This is the id the tutor's actions target — see `TutorAction.target`.
  final String id;

  /// What the mark means: `angle`, `side`, `unknown`, `equation`, … Kept as a
  /// plain string on purpose: the server owns the vocabulary, and a build that
  /// doesn't know a newer type should still be able to draw the box.
  final String type;

  /// The mark as written — "28°", "x", "AB".
  final String label;

  /// Where it is, as fractions of the image: `Rect.fromLTWH(0.42, 0.13, …)`.
  final Rect rect;

  /// The teaching colour this concept wears, shared with in-equation
  /// highlighting so a student learns the vocabulary once.
  final MathRole role;

  /// The vertex an angle sits at, when the scanner could tell. Absent rather
  /// than guessed — an angle attributed to the wrong corner is worse than an
  /// unnamed one.
  final String? vertex;

  /// How sure the reader was of this mark, 0–1.
  final double confidence;

  /// Parse the `anchors` array from a scan or tutor payload.
  ///
  /// Defensive throughout, for the same reason the server is: these numbers
  /// become rectangles drawn over a student's own homework. Anything unusable is
  /// dropped rather than repaired — one fewer place to point is a small loss;
  /// an outline around the wrong symbol is a wrong answer with a highlighter.
  static List<ScanAnchor> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    final out = <ScanAnchor>[];
    final seen = <String>{};
    for (final item in raw) {
      final anchor = fromJson(item);
      if (anchor == null || !seen.add(anchor.id)) continue;
      out.add(anchor);
    }
    return out;
  }

  static ScanAnchor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final id = map['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final rect = _rect(map['box']);
    if (rect == null) return null;
    final vertex = map['vertex'];
    return ScanAnchor(
      id: id.trim(),
      type: map['type'] is String ? (map['type'] as String).trim() : 'label',
      label: map['label'] is String ? (map['label'] as String).trim() : id.trim(),
      rect: rect,
      role: MathRole.parse(map['role'] is String ? map['role'] as String : null),
      vertex: vertex is String && vertex.trim().isNotEmpty ? vertex.trim() : null,
      confidence: map['confidence'] is num
          ? (map['confidence'] as num).toDouble().clamp(0.0, 1.0)
          : 0.5,
    );
  }

  /// The smallest box worth outlining, as a fraction of the frame. Mirrors the
  /// server's own floor so the two ends agree on what is drawable.
  static const double minSize = 0.004;

  static Rect? _rect(Object? raw) {
    if (raw is! Map) return null;
    final x = raw['x'], y = raw['y'], w = raw['w'], h = raw['h'];
    if (x is! num || y is! num || w is! num || h is! num) return null;
    final dx = x.toDouble(), dy = y.toDouble();
    final dw = w.toDouble(), dh = h.toDouble();
    if (!dx.isFinite || !dy.isFinite || !dw.isFinite || !dh.isFinite) return null;
    if (dx < 0 || dy < 0 || dx > 1 || dy > 1) return null;
    // Trim the overhang of a mark cropped at the margin rather than losing it.
    final right = dw + dx > 1 ? 1.0 : dx + dw;
    final bottom = dh + dy > 1 ? 1.0 : dy + dh;
    if (right - dx < minSize || bottom - dy < minSize) return null;
    return Rect.fromLTRB(dx, dy, right, bottom);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'label': label,
        'role': role.name,
        if (vertex != null) 'vertex': vertex,
        'box': {'x': rect.left, 'y': rect.top, 'w': rect.width, 'h': rect.height},
        'confidence': confidence,
      };

  /// Scale into a laid-out image of [size]-by-[size] pixels.
  Rect toPixels(double width, double height) => Rect.fromLTRB(
        rect.left * width,
        rect.top * height,
        rect.right * width,
        rect.bottom * height,
      );

  /// How the anchor reads aloud, for the screen reader — position and role, not
  /// value, which is the same discipline the tutor's prose follows.
  String get semanticLabel {
    final where = vertex != null ? ' at vertex $vertex' : '';
    return '$type$where, $label';
  }

  @override
  bool operator ==(Object other) =>
      other is ScanAnchor &&
      other.id == id &&
      other.type == type &&
      other.label == label &&
      other.rect == rect &&
      other.role == role &&
      other.vertex == vertex;

  @override
  int get hashCode => Object.hash(id, type, label, rect, role, vertex);

  @override
  String toString() => 'ScanAnchor($id, $label, $rect)';
}
