/// GEOMETRY VISUAL LEARNING — automatic detection.
///
/// A tiny, deterministic keyword classifier that answers "is this a geometry
/// problem?" from the problem text/LaTeX. It's used as a cheap client-side
/// signal (e.g. to prefer the diagram-first player, or for analytics); the
/// authoritative structured geometry data still comes from the solver/visual
/// backend. Keeping it a pure function makes it trivially testable.
class GeometryDetector {
  const GeometryDetector._();

  /// The geometry vocabulary from the spec, plus close synonyms that show up in
  /// the same problems. Matched case-insensitively on word boundaries so
  /// "triangle" hits but "strangle" does not, and "angle" hits but "mangle"
  /// (or LaTeX like `\rangle`) does not.
  static const List<String> keywords = [
    'triangle',
    'angle',
    'circle',
    'parallel line',
    'parallel lines',
    'polygon',
    'geometry',
    // Common companions of the six spec keywords.
    'quadrilateral',
    'pentagon',
    'hexagon',
    'isosceles',
    'equilateral',
    'transversal',
    'vertex',
    'vertices',
    'perpendicular',
    'radius',
    'diameter',
    'circumference',
    'interior angle',
    'exterior angle',
  ];

  // A trailing `s?` lets a keyword match its plural too ("angles", "triangles",
  // "parallel lines") without listing every plural. Boundaries keep it from
  // firing inside longer words ("strangle", LaTeX `\rangle`).
  static final RegExp _pattern = RegExp(
    r'\b(?:' +
        keywords.map(RegExp.escape).join('|') +
        r')s?\b',
    caseSensitive: false,
  );

  /// Whether [problem] (LaTeX or plain text) reads as a geometry problem.
  static bool isGeometry(String? problem) {
    if (problem == null || problem.isEmpty) return false;
    return _pattern.hasMatch(problem);
  }

  /// The distinct geometry keywords that matched, in first-seen order — handy
  /// for analytics/debugging and for tests to assert on.
  static List<String> matchedKeywords(String? problem) {
    if (problem == null || problem.isEmpty) return const [];
    final seen = <String>{};
    for (final m in _pattern.allMatches(problem)) {
      seen.add(m.group(0)!.toLowerCase());
    }
    return seen.toList();
  }
}
