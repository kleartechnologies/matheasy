import '../../domain/animation/eq_token.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — turns a delimiter-free LaTeX equation
/// into an ordered list of [EqToken]s (signed terms + the relation symbol).
///
/// This is a *pragmatic* tokenizer, NOT a full TeX parser: it is tuned to the
/// canonical LaTeX the deterministic solver emits (mathsteps/mathjs). It splits
/// on the top-level relation and then on top-level `+`/`-`, respecting brace,
/// paren and bracket depth so a `\frac{a-b}{c}` or `x^{-2}` is never torn apart.
/// It NEVER throws: anything it can't confidently split degrades to a single
/// whole-expression token (which the diff then crossfades).
class EquationTokenizer {
  const EquationTokenizer._();

  /// A safety cap — a pathological input never produces a runaway token list.
  static const int _maxTerms = 24;

  /// Tokenize [rawLatex]. Returns `[]` for blank input.
  static List<EqToken> tokenize(String rawLatex) {
    final s = _normalize(rawLatex);
    if (s.isEmpty) return const [];

    final rel = _findRelation(s);
    final tokens = <EqToken>[];
    var nextId = 0;

    if (rel == null) {
      _emitSide(s, side: -1, tokens: tokens, nextId: () => nextId++);
    } else {
      final left = s.substring(0, rel.start).trim();
      final right = s.substring(rel.end).trim();
      _emitSide(left, side: 0, tokens: tokens, nextId: () => nextId++);
      tokens.add(EqToken(
        id: nextId++,
        latex: rel.relation.latex,
        kind: EqTokenKind.relation,
        side: -1,
        sign: 1,
        key: '__rel__',
      ));
      _emitSide(right, side: 1, tokens: tokens, nextId: () => nextId++);
    }

    // Over the term cap (a degenerate parse) → collapse to a single token so the
    // renderer safely crossfades instead of animating nonsense.
    final termCount = tokens.where((t) => t.isTerm).length;
    if (termCount == 0 || termCount > _maxTerms) {
      return [
        EqToken(
          id: 0,
          latex: s,
          kind: EqTokenKind.term,
          side: -1,
          sign: 1,
          key: s.replaceAll(' ', ''),
        ),
      ];
    }
    return tokens;
  }

  // ---- normalization --------------------------------------------------------

  static String _normalize(String input) {
    var s = input.trim();
    // Strip common math delimiters.
    for (final d in const [r'\(', r'\)', r'\[', r'\]']) {
      s = s.replaceAll(d, ' ');
    }
    s = s.replaceAll(r'$', ' ');
    // \left( / \right) are depth-neutral wrappers — drop them, keep the bracket.
    s = s.replaceAll(r'\left', ' ').replaceAll(r'\right', ' ');
    // Thin spaces / layout directives → plain space.
    for (final d in const [
      r'\displaystyle',
      r'\,',
      r'\;',
      r'\:',
      r'\!',
      r'\quad',
      r'\qquad',
    ]) {
      s = s.replaceAll(d, ' ');
    }
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ---- relation detection ---------------------------------------------------

  static _RelHit? _findRelation(String s) {
    var depth = 0;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') depth--;
      if (depth != 0) continue;
      if (s.startsWith(r'\leq', i)) return _RelHit(i, i + 4, EqRelation.le);
      if (s.startsWith(r'\geq', i)) return _RelHit(i, i + 4, EqRelation.ge);
      if (s.startsWith(r'\le', i)) return _RelHit(i, i + 3, EqRelation.le);
      if (s.startsWith(r'\ge', i)) return _RelHit(i, i + 3, EqRelation.ge);
      if (c == '=') return _RelHit(i, i + 1, EqRelation.equals);
      if (c == '<') return _RelHit(i, i + 1, EqRelation.lt);
      if (c == '>') return _RelHit(i, i + 1, EqRelation.gt);
    }
    return null;
  }

  // ---- term splitting -------------------------------------------------------

  static void _emitSide(
    String sideStr, {
    required int side,
    required List<EqToken> tokens,
    required int Function() nextId,
  }) {
    final raw = _splitTerms(sideStr);
    var first = true;
    for (final piece in raw) {
      final t = piece.trim();
      if (t.isEmpty) continue;
      final sign = t.startsWith('-') ? -1 : 1;
      var body = t;
      if (body.startsWith('+') || body.startsWith('-')) {
        body = body.substring(1).trim();
      }
      if (body.isEmpty) continue;
      final latex = first
          ? (sign < 0 ? '-$body' : body)
          : (sign < 0 ? '- $body' : '+ $body');
      tokens.add(EqToken(
        id: nextId(),
        latex: latex,
        kind: EqTokenKind.term,
        side: side,
        sign: sign,
        key: body.replaceAll(' ', ''),
      ));
      first = false;
    }
  }

  static List<String> _splitTerms(String side) {
    final out = <String>[];
    var depth = 0;
    var start = 0;
    String lastSig = '';
    for (var i = 0; i < side.length; i++) {
      final c = side[i];
      if (c == '(' || c == '[' || c == '{') depth++;
      if (c == ')' || c == ']' || c == '}') depth--;
      final isSep = depth == 0 &&
          (c == '+' || c == '-') &&
          i > 0 &&
          !_isOperatorChar(lastSig);
      if (isSep) {
        out.add(side.substring(start, i));
        start = i;
      }
      if (c != ' ') lastSig = c;
    }
    out.add(side.substring(start));
    return out;
  }

  /// A `+`/`-` right after one of these is a unary sign, not a term separator.
  static bool _isOperatorChar(String c) =>
      c == '+' ||
      c == '-' ||
      c == '*' ||
      c == '/' ||
      c == '^' ||
      c == '_' ||
      c == '(' ||
      c == '[' ||
      c == '\\' ||
      c == '=';
}

/// A detected top-level relation and its position in the source string.
class _RelHit {
  const _RelHit(this.start, this.end, this.relation);
  final int start;
  final int end;
  final EqRelation relation;
}
