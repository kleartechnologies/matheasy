import 'dart:ui' show Offset;

import '../../domain/animation/scene_spec.dart';
import '../../domain/result_models.dart';
import 'equation_tokenizer.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — deterministic "visual object" builders.
///
/// Each `tryBuild` mirrors the `GeometryScene.tryBuild` discipline: it reads the
/// *verified* solve (the equation sides, the server-sampled curve, the answer
/// fraction) and returns a drawable [SceneObject], or `null` when the data
/// doesn't fit — in which case the player shows the equation morph alone. No
/// arithmetic happens here; a scene only *positions* already-verified values.
class SceneBuilders {
  const SceneBuilders._();

  /// A two-pan balance for a linear equation: the left and right sides as chips.
  /// The balance never computes — it just displays the verified sides and, on
  /// the answer beat, the solved value. `null` when the input has no relation.
  static SceneObject? balanceScale({
    required String equationLatex,
    required String answerLatex,
  }) {
    final tokens = EquationTokenizer.tokenize(equationLatex);
    final rel = tokens.where((t) => t.isRelation).toList();
    if (rel.isEmpty || rel.first.latex != '=') return null;
    final left = tokens.where((t) => t.isTerm && t.side == 0).toList();
    final right = tokens.where((t) => t.isTerm && t.side == 1).toList();
    if (left.isEmpty || right.isEmpty) return null;
    // Too many chips per pan would overflow the little scale — keep it legible.
    if (left.length > 4 || right.length > 4) return null;
    final leftLatex = left.map((t) => t.latex).join(' ');
    final rightLatex = right.map((t) => t.latex).join(' ');
    return SceneObject(
      kind: SceneObjectKind.balanceScale,
      caption: 'A balance scale: whatever you do to one side, do to the other.',
      labels: {
        'left': leftLatex,
        'right': rightLatex,
        if (answerLatex.trim().isNotEmpty) 'answer': answerLatex.trim(),
      },
    );
  }

  /// A curve/parabola from the server-sampled (verified) graph points.
  static SceneObject? graph({
    required GraphData? graph,
    required ResultType type,
  }) {
    final g = graph;
    if (g == null || g.curve.length < 4) return null;
    // The samples are already (x, y) in maths coordinates; the painter frames them.
    final points = <Offset>[for (final o in g.curve) o];
    final roots = g.keyPoints
        .where((k) => k.label.toLowerCase().contains('root') ||
            k.label.toLowerCase().contains('intercept') ||
            k.label.toLowerCase().contains('zero'))
        .toList();
    final params = <String, double>{
      'roots': roots.length.toDouble(),
      for (var i = 0; i < roots.length && i < 3; i++) 'rootX$i': roots[i].x,
    };
    // A vertex / turning point, if the server labelled one.
    final vertex = g.keyPoints.where((k) {
      final l = k.label.toLowerCase();
      return l.contains('vertex') || l.contains('turning') || l.contains('min') ||
          l.contains('max');
    }).toList();
    if (vertex.isNotEmpty) {
      params['vertexX'] = vertex.first.x;
      params['vertexY'] = vertex.first.y;
      params['hasVertex'] = 1;
    }
    return SceneObject(
      kind: type == ResultType.quadratic
          ? SceneObjectKind.parabola
          : SceneObjectKind.curve,
      caption: 'The graph of ${g.expression}.',
      params: params,
      labels: {'expression': g.expression},
      points: points,
    );
  }

  /// A single fraction bar for a fraction ANSWER (e.g. `\frac{3}{4}`). Golden
  /// rule: it is built ONLY from the verified answer (never a problem operand),
  /// and only for a **proper, non-negative** fraction — a bar of a whole can't
  /// honestly depict a negative or improper value, so anything else degrades to
  /// the morph rather than paint a figure that contradicts the answer.
  static SceneObject? fractionBar({
    required String problemLatex,
    required String answerLatex,
  }) {
    final frac = _firstFraction(answerLatex);
    if (frac == null) return null;
    final (num, den) = frac;
    if (den < 2 || den > 24) return null;
    if (num < 0 || num > den) return null; // negative/improper → morph only
    return SceneObject(
      kind: SceneObjectKind.fractionBar,
      caption: 'A bar split into $den equal parts, $num shaded.',
      params: {'numerator': num.toDouble(), 'denominator': den.toDouble()},
    );
  }

  // Captures an optional leading minus BEFORE `\frac` too, so `-\frac{3}{4}` is
  // seen as negative (and rejected) rather than silently shown as `3/4`.
  static final RegExp _fracRe = RegExp(r'(-)?\\frac\{(-?\d+)\}\{(\d+)\}');

  /// The first (signed) `\frac{p}{q}` in [latex], as `(p, q)`, or `null`.
  static (int, int)? _firstFraction(String latex) {
    final m = _fracRe.firstMatch(latex);
    if (m == null) return null;
    final lead = m.group(1) == '-' ? -1 : 1;
    final p = int.tryParse(m.group(2) ?? '');
    final q = int.tryParse(m.group(3) ?? '');
    if (p == null || q == null || q == 0) return null;
    return (lead * p, q);
  }
}
