import '../domain/geometry_models.dart';

/// Parses the structured `geometry` JSON — emitted by BOTH the
/// `generateVisualSolution` (Visual tab) and `recognizeEquation` (scan) backends
/// — into a solved [GeometryScene], or `null` when it's absent, malformed,
/// unsupported, or inconsistent.
///
/// It only relays the model's *given facts*; the actual arithmetic (the missing
/// angle or side) is computed inside [GeometryScene] (the golden rule). Sharing
/// one mapper keeps the two backends' contracts in lockstep.
class GeometryPayloadMapper {
  const GeometryPayloadMapper._();

  /// The full geometry vocabulary the backends may emit, kept in sync with the
  /// server prompts.
  static GeometryScene? parse(Object? json, {String? expectedAnswerLatex}) {
    if (json is! Map) return null;
    final m = Map<String, dynamic>.from(json);

    final kind = _enumByName(GeometrySceneKind.values, m['kind']);
    if (kind == null) return null;

    final expected = (expectedAnswerLatex != null &&
            expectedAnswerLatex.isNotEmpty)
        ? expectedAnswerLatex
        : null;

    if (kind == GeometrySceneKind.rightTrianglePythagoras) {
      return _pythagoras(m, expected);
    }
    if (kind == GeometrySceneKind.rightTriangleTrig) {
      return _rightTriangleTrig(m, expected);
    }
    if (kind == GeometrySceneKind.rightTriangleInverseTrig) {
      return _rightTriangleInverseTrig(m, expected);
    }
    if (kind == GeometrySceneKind.sineRuleAngle) {
      return _sineRuleAngle(m, expected);
    }
    if (kind == GeometrySceneKind.sasArea) {
      return _sasArea(m, expected);
    }
    if (kind == GeometrySceneKind.cosineRuleSide) {
      return _cosineRuleSide(m, expected);
    }
    if (kind == GeometrySceneKind.cosineRuleAngle) {
      return _cosineRuleAngle(m, expected);
    }
    return _angles(kind, m, expected);
  }

  // ---- Angle problems -------------------------------------------------------

  static GeometryScene? _angles(
    GeometrySceneKind kind,
    Map<String, dynamic> m,
    String? expected,
  ) {
    final knowns = _knownAngles(m['knownAngles']);
    if (knowns.isEmpty) return null;
    return GeometryScene.tryBuild(
      kind: kind,
      knownAngles: knowns,
      unknownLabel: _unknownLabel(m['unknown']),
      // Polygon side count: `polygonSides` (recognizer) or `sides` (visual
      // backend) — the latter is an int there, but a Pythagoras `sides` array
      // never reaches this angle path, so `_int` of it harmlessly yields null.
      sides: _int(m['polygonSides']) ?? _int(m['sides']),
      relation: _enumByName(GeometryRelation.values, m['relation']),
      relationReference: _optional(m['relationReference']),
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  /// `knownAngles`: `[{label, value}, ...]`; entries without a finite numeric
  /// value are skipped, and a missing label gets a sequential letter.
  static List<GeometryKnownAngle> _knownAngles(Object? v) {
    if (v is! List) return const [];
    final out = <GeometryKnownAngle>[];
    for (final e in v) {
      if (e is! Map) continue;
      final value = _num(e['value']);
      if (value == null) continue;
      final rawLabel = e['label'];
      final label = rawLabel is String && rawLabel.trim().isNotEmpty
          ? rawLabel.trim()
          : String.fromCharCode('a'.codeUnitAt(0) + out.length);
      out.add(GeometryKnownAngle(label: label, value: value));
    }
    return out;
  }

  // ---- Pythagoras -----------------------------------------------------------

  static GeometryScene? _pythagoras(Map<String, dynamic> m, String? expected) {
    final sides = _knownSides(m['sides']);
    if (sides.length != 3) return null;
    return GeometryScene.tryBuildPythagoras(
      sides: sides,
      unknownLabel: _unknownLabel(m['unknown']),
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  /// `sides`: `[{label, role, value?}, ...]` — a `null`/absent value marks the
  /// unknown. An unrecognised role or a bad shape yields an empty/short list so
  /// [GeometryScene.tryBuildPythagoras] rejects it.
  static List<GeometryKnownSide> _knownSides(Object? v) {
    if (v is! List) return const [];
    final out = <GeometryKnownSide>[];
    for (final e in v) {
      if (e is! Map) continue;
      final role = _enumByName(GeometrySideRole.values, e['role']);
      if (role == null) return const []; // an unknown role invalidates the set
      final rawLabel = e['label'];
      final label = rawLabel is String && rawLabel.trim().isNotEmpty
          ? rawLabel.trim()
          : String.fromCharCode('a'.codeUnitAt(0) + out.length);
      out.add(GeometryKnownSide(
        label: label,
        role: role,
        value: _num(e['value']), // null ⇒ the unknown
      ));
    }
    return out;
  }

  // ---- Right-triangle trig (side from a side + an acute angle) --------------

  static GeometryScene? _rightTriangleTrig(
    Map<String, dynamic> m,
    String? expected,
  ) {
    final angle = _labeledValue(m['knownAngle']);
    if (angle == null) return null;
    final sides = _trigSides(m['sides']);
    if (sides == null) return null;
    return GeometryScene.tryBuildRightTriangleTrig(
      knownAngleDeg: angle.value,
      knownAngleLabel: angle.label,
      sides: sides,
      unknownLabel: _unknownLabel(m['unknown']),
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  // ---- Right-triangle inverse trig (an acute angle from two sides) ----------

  static GeometryScene? _rightTriangleInverseTrig(
    Map<String, dynamic> m,
    String? expected,
  ) {
    final sides = _trigSides(m['sides']);
    if (sides == null) return null;
    // Exactly two GIVEN sides (both valued) — the unknown of this kind is the
    // ANGLE, so a blank side means a mis-filed side-finding problem; the builder
    // enforces the same, this just short-circuits the common case.
    if (sides.length != 2 || sides.any((s) => s.value == null)) return null;
    return GeometryScene.tryBuildRightTriangleInverseTrig(
      sides: sides,
      unknownLabel: _unknownLabel(m['unknown']),
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  /// `sides`: `[{label, role, value?}, ...]` with roles relative to the known
  /// angle — a `null`/absent value marks the unknown. An unrecognised role
  /// invalidates the whole set (the builder then rejects the short list).
  static List<GeometryTrigSide>? _trigSides(Object? v) {
    if (v is! List) return null;
    final out = <GeometryTrigSide>[];
    for (final e in v) {
      if (e is! Map) continue;
      final role = _enumByName(GeometryTrigSideRole.values, e['role']);
      if (role == null) return null; // an unknown role invalidates the set
      final rawLabel = e['label'];
      final label = rawLabel is String && rawLabel.trim().isNotEmpty
          ? rawLabel.trim()
          : String.fromCharCode('a'.codeUnitAt(0) + out.length);
      out.add(GeometryTrigSide(label: label, role: role, value: _num(e['value'])));
    }
    return out;
  }

  // ---- Sine rule (angle from two sides + a non-included angle) --------------

  static GeometryScene? _sineRuleAngle(
    Map<String, dynamic> m,
    String? expected,
  ) {
    final knownAngle = _labeledValue(m['knownAngle']);
    final sideOppositeKnown = _labeledValue(m['sideOppositeKnown']);
    final sideOppositeUnknown = _labeledValue(m['sideOppositeUnknown']);
    if (knownAngle == null ||
        sideOppositeKnown == null ||
        sideOppositeUnknown == null) {
      return null;
    }
    return GeometryScene.tryBuildSineRuleAngle(
      knownAngleDeg: knownAngle.value,
      knownAngleLabel: knownAngle.label,
      sideOppositeKnown: sideOppositeKnown.value,
      sideOppositeKnownLabel: sideOppositeKnown.label,
      sideOppositeUnknown: sideOppositeUnknown.value,
      sideOppositeUnknownLabel: sideOppositeUnknown.label,
      unknownLabel: _unknownLabel(m['unknown']),
      branch: _enumByName(AngleBranchHint.values, m['angleBranch']),
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  // ---- SAS area (two sides + the included angle) ------------------------------

  static GeometryScene? _sasArea(Map<String, dynamic> m, String? expected) {
    final angle = _labeledValue(m['includedAngle']);
    if (angle == null) return null;
    final raw = m['sides'];
    if (raw is! List || raw.length != 2) return null;
    final a = raw[0] is Map ? _labeledValue(raw[0]) : null;
    final b = raw[1] is Map ? _labeledValue(raw[1]) : null;
    if (a == null || b == null) return null;
    final unknown = m['unknown'];
    final rawUnknown = unknown is String ? unknown.trim() : '';
    // The unknown of this kind IS the area. A side-style unknown ("x") means
    // the recognizer misfiled a cosine-rule "find the third side" problem —
    // computing an AREA and labelling it x would be a confident wrong answer,
    // so refuse the scene entirely (the normal solver flow takes over).
    if (rawUnknown.isNotEmpty && rawUnknown.toLowerCase() != 'area') {
      return null;
    }
    return GeometryScene.tryBuildSasArea(
      sideA: a.value,
      sideALabel: a.label,
      sideB: b.value,
      sideBLabel: b.label,
      includedAngleDeg: angle.value,
      angleLabel: angle.label,
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  // ---- Cosine rule (SAS → the third side; SSS → an angle) -------------------

  static GeometryScene? _cosineRuleSide(Map<String, dynamic> m, String? expected) {
    final angle = _labeledValue(m['includedAngle']);
    if (angle == null) return null;
    final raw = m['sides'];
    if (raw is! List || raw.length != 2) return null;
    final a = raw[0] is Map ? _labeledValue(raw[0]) : null;
    final b = raw[1] is Map ? _labeledValue(raw[1]) : null;
    if (a == null || b == null) return null;
    // The unknown of this kind IS the third SIDE. cosineRuleSide and sasArea
    // share an identical shape (two sides + the included angle), so an AREA
    // problem misfiled here would compute a SIDE and label it "Area" — a
    // confident wrong answer. Refuse it (mirrors the reciprocal guard in
    // _sasArea); the normal solver/tutor flow then handles the area.
    final rawUnknown = m['unknown'] is String ? (m['unknown'] as String).trim() : '';
    if (rawUnknown.toLowerCase() == 'area') return null;
    return GeometryScene.tryBuildCosineRuleSide(
      sideA: a.value,
      sideALabel: a.label,
      sideB: b.value,
      sideBLabel: b.label,
      includedAngleDeg: angle.value,
      angleLabel: angle.label,
      unknownLabel: _unknownLabel(m['unknown']),
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  /// `sides`: three `{label, value}`; `oppositeSide` names which side is opposite
  /// the asked angle (the other two are the adjacent pair). A missing/unmatched
  /// `oppositeSide`, a wrong side count, or a bad value rejects the scene.
  static GeometryScene? _cosineRuleAngle(
    Map<String, dynamic> m,
    String? expected,
  ) {
    final raw = m['sides'];
    if (raw is! List || raw.length != 3) return null;
    final sides = <({String label, double value})>[];
    for (final e in raw) {
      final lv = e is Map ? _labeledValue(e) : null;
      if (lv == null) return null;
      sides.add(lv);
    }
    final oppLabel = _optional(m['oppositeSide']);
    if (oppLabel == null) return null;
    final oppIdx = sides.indexWhere((s) => s.label == oppLabel);
    if (oppIdx < 0) return null;
    final opp = sides[oppIdx];
    final adj = [
      for (var i = 0; i < sides.length; i++)
        if (i != oppIdx) sides[i],
    ];
    if (adj.length != 2) return null;
    return GeometryScene.tryBuildCosineRuleAngle(
      oppositeSide: opp.value,
      oppositeSideLabel: opp.label,
      adjSide1: adj[0].value,
      adjSide1Label: adj[0].label,
      adjSide2: adj[1].value,
      adjSide2Label: adj[1].label,
      unknownLabel: _unknownLabel(m['unknown']),
      ruleName: _optional(m['ruleName']),
      caption: _optional(m['caption']),
      expectedAnswerLatex: expected,
    );
  }

  /// `{label, value}` → a (label, value) pair; a missing/blank label becomes
  /// `''` (the builders substitute their own defaults), a non-finite value
  /// rejects the entry.
  static ({String label, double value})? _labeledValue(Object? v) {
    if (v is! Map) return null;
    final value = _num(v['value']);
    if (value == null) return null;
    final rawLabel = v['label'];
    final label =
        rawLabel is String && rawLabel.trim().isNotEmpty ? rawLabel.trim() : '';
    return (label: label, value: value);
  }

  // ---- Shared coercions -----------------------------------------------------

  static String _unknownLabel(Object? v) {
    String? raw;
    if (v is String) {
      raw = v.trim();
    } else if (v is Map && v['label'] is String) {
      raw = (v['label'] as String).trim();
    }
    if (raw == null || raw.isEmpty || raw.length > 12) return 'x';
    return raw;
  }

  static String? _optional(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _num(Object? v) {
    final double? d;
    if (v is num) {
      d = v.toDouble();
    } else if (v is String) {
      // The prompt demands bare numbers, but a model reading "35°" off a
      // figure sometimes keeps the mark — stripping it loses nothing (the
      // value is still the GIVEN, in degrees) and saves the whole scene.
      final cleaned =
          v.replaceAll('°', '').replaceAll(RegExp(r'\^?\\circ'), '').trim();
      d = double.tryParse(cleaned);
    } else {
      d = null;
    }
    if (d == null || !d.isFinite) return null;
    return d;
  }

  static T? _enumByName<T extends Enum>(List<T> values, Object? name) {
    if (name is! String) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
