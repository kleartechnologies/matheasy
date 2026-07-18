/// Presentation-only LaTeX helpers for the result screen.
///
/// These reshape how math is *displayed* and estimate its on-screen width so the
/// answer/steps can be sized adaptively. They NEVER change a mathematical value:
/// the golden rule (the server computes and verifies the answer) is untouched —
/// this only affects typesetting. `\frac`-folding turns an inline `a/b` into a
/// stacked fraction; the number it represents is identical.
library;

// ---------------------------------------------------------------------------
// Display normalization — inline division → proper stacked fractions
// ---------------------------------------------------------------------------

/// Upgrades inline division to a proper stacked fraction for display, so an
/// expression like `(12p+9q)/(p^2-q^2)` renders as
///
///     12p+9q
///     ──────
///     p²−q²
///
/// instead of inline text with a slash.
///
/// Conservative and idempotent: it only rewrites a `/` whose numerator and
/// denominator are cleanly identifiable operands at the same nesting level,
/// leaves existing `\frac`, `\text{…}`, and control words like `\\` untouched,
/// recurses into `(…)`/`[…]` groups so nested quotients also fold, and returns
/// the original string unchanged if anything unexpected happens (display must
/// never break).
String toDisplayLatex(String latex) {
  if (!latex.contains('/')) return latex;
  try {
    return _foldFractions(_foldDerivativeOperator(latex));
  } catch (_) {
    return latex;
  }
}

/// Stacks the Leibniz derivative operator applied to an argument —
/// `d/dx(…)`, `d^2/dx^2(…)`, `∂/∂x(…)` — into `\frac{d}{dx}` etc. The general
/// fold deliberately skips these (the `dx(` reads as function application), so
/// they get a dedicated, tightly-anchored rule. A bare `d/dx` with no argument
/// is already handled by the general fold.
String _foldDerivativeOperator(String s) {
  return s.replaceAllMapped(
    RegExp(r'(?<![A-Za-z\\])([d∂])(\^\{?\d+\}?)?/([d∂])([A-Za-z])(\^\{?\d+\}?)?'
        r'(?=\s*[({])'),
    (m) => '\\frac{${m[1]}${m[2] ?? ''}}{${m[3]}${m[4]}${m[5] ?? ''}}',
  );
}

String _foldFractions(String src) {
  final atoms = _tokenize(src);
  // Recurse into bracket groups first so inner slashes fold too.
  for (final a in atoms) {
    if (a.kind == _Kind.group) {
      a.text = a.open + _foldFractions(a.inner) + a.close + a.scripts;
    }
  }
  // Fold `<operand> / <operand>` left-to-right.
  final out = <_Atom>[];
  for (var i = 0; i < atoms.length; i++) {
    final a = atoms[i];
    if (a.kind == _Kind.slash && out.isNotEmpty) {
      // Skip whitespace between the slash and the next operand…
      var j = i + 1;
      while (j < atoms.length && atoms[j].kind == _Kind.space) {
        j++;
      }
      // …and any whitespace already emitted before the slash.
      var k = out.length - 1;
      while (k >= 0 && out[k].kind == _Kind.space) {
        k--;
      }
      // Only fold when both sides are single, unambiguous operands. Bail when an
      // operand is directly juxtaposed with a neighbour (no space/operator
      // between) — that is function application or implicit multiplication, e.g.
      // `\sin(x)/2` or `a/f(x)`, where the real numerator/denominator is the
      // whole `\sin(x)` / `f(x)`. Leaving those as an inline slash is safe (no
      // regression); mis-grouping them would change the meaning.
      final numOk = k >= 0 &&
          out[k].isOperand &&
          (k == 0 || !out[k - 1].isOperand);
      final denOk = j < atoms.length &&
          atoms[j].isOperand &&
          (j + 1 >= atoms.length || !atoms[j + 1].isOperand);
      if (numOk && denOk) {
        final num = _stripOuterParens(out[k].text);
        final den = _stripOuterParens(atoms[j].text);
        out.removeRange(k, out.length); // drop numerator + trailing spaces
        out.add(_Atom(_Kind.group, r'\frac{' '$num' '}{' '$den' '}'));
        i = j; // consume the denominator (and any skipped spaces)
        continue;
      }
    }
    out.add(a);
  }
  return out.map((a) => a.text).join();
}

/// Removes one layer of balanced outer parentheses, e.g. `(a+b)` → `a+b`. Leaves
/// `(a)(b)` alone (the outer parens aren't a single wrapping pair).
String _stripOuterParens(String s) {
  final t = s.trim();
  if (t.length < 2 || !t.startsWith('(') || !t.endsWith(')')) return s;
  var depth = 0;
  for (var i = 0; i < t.length; i++) {
    final c = t[i];
    if (c == '(') {
      depth++;
    } else if (c == ')') {
      depth--;
      if (depth == 0 && i != t.length - 1) return s; // closes early → not wrapping
    }
  }
  return t.substring(1, t.length - 1);
}

enum _Kind { operand, slash, op, space, group }

class _Atom {
  _Atom(
    this.kind,
    this.text, {
    this.open = '',
    this.inner = '',
    this.close = '',
    this.scripts = '',
  });

  final _Kind kind;
  String text;

  /// For `_Kind.group`: the opening bracket, its raw contents, its closing
  /// bracket, and any `^`/`_` scripts that trailed the group (e.g. the `^2` in
  /// `(a+b)^2`) — kept separate so recursion can rebuild `open+inner+close+scripts`.
  final String open;
  final String inner;
  final String close;
  final String scripts;

  bool get isOperand => kind == _Kind.operand || kind == _Kind.group;
}

const _openers = {'(': ')', '[': ']', '{': '}'};

/// Splits a LaTeX string into top-level atoms: operands (numbers, identifiers,
/// commands with their `{}`/`[]` arguments, plus any trailing `^`/`_` scripts),
/// bracket groups (recursed later), slashes, operators and whitespace.
List<_Atom> _tokenize(String s) {
  final atoms = <_Atom>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == ' ' || c == '\t' || c == '\n') {
      final start = i;
      while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\n')) {
        i++;
      }
      atoms.add(_Atom(_Kind.space, s.substring(start, i)));
      continue;
    }
    if (c == '/') {
      atoms.add(_Atom(_Kind.slash, '/'));
      i++;
      continue;
    }
    if (_openers.containsKey(c)) {
      final close = _openers[c]!;
      final end = _matchGroup(s, i, c, close);
      final inner = s.substring(i + 1, end);
      i = end + 1;
      final (scripts, next) = _readScripts(s, i);
      i = next;
      atoms.add(_Atom(_Kind.group, '$c$inner$close$scripts',
          open: c, inner: inner, close: close, scripts: scripts));
      continue;
    }
    if (c == r'\') {
      // A command: backslash + letters, or a control symbol (backslash + one
      // non-letter, e.g. `\\`, `\,`). Named commands absorb following {…}/[…]
      // arguments so `\frac{a}{b}` and `\sqrt[n]{x}` stay a single operand.
      final start = i;
      i++;
      if (i < s.length && _isLetter(s[i])) {
        while (i < s.length && _isLetter(s[i])) {
          i++;
        }
        while (i < s.length && (s[i] == '{' || s[i] == '[')) {
          final open = s[i];
          final end = _matchGroup(s, i, open, _openers[open]!);
          i = end + 1;
        }
        final body = s.substring(start, i);
        final (scripts, next) = _readScripts(s, i);
        i = next;
        atoms.add(_Atom(_Kind.operand, body + scripts));
      } else {
        // Control symbol like `\\`, `\,`, `\;` — acts as an operator.
        if (i < s.length) i++;
        atoms.add(_Atom(_Kind.op, s.substring(start, i)));
      }
      continue;
    }
    if (_isAlnum(c) || c == '.') {
      final start = i;
      while (i < s.length && (_isAlnum(s[i]) || s[i] == '.')) {
        i++;
      }
      final body = s.substring(start, i);
      final (scripts, next) = _readScripts(s, i);
      i = next;
      atoms.add(_Atom(_Kind.operand, body + scripts));
      continue;
    }
    // Everything else (+, -, =, &, |, …) is an operator.
    atoms.add(_Atom(_Kind.op, c));
    i++;
  }
  return atoms;
}

/// Reads a run of `^`/`_` scripts (with their `{…}`/command/single-char
/// arguments) starting at [i], returning the consumed text and the new index.
(String, int) _readScripts(String s, int i) {
  final buf = StringBuffer();
  while (i < s.length && (s[i] == '^' || s[i] == '_')) {
    buf.write(s[i]);
    i++;
    if (i < s.length && s[i] == '{') {
      final end = _matchGroup(s, i, '{', '}');
      buf.write(s.substring(i, end + 1));
      i = end + 1;
    } else if (i < s.length && s[i] == r'\') {
      final start = i;
      i++;
      while (i < s.length && _isLetter(s[i])) {
        i++;
      }
      buf.write(s.substring(start, i));
    } else if (i < s.length) {
      buf.write(s[i]);
      i++;
    }
  }
  return (buf.toString(), i);
}

int _matchGroup(String s, int open, String o, String c) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == o) {
      depth++;
    } else if (s[i] == c) {
      depth--;
      if (depth == 0) return i;
    }
  }
  throw const FormatException('unbalanced group');
}

bool _isLetter(String c) =>
    (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 90) ||
    (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 122);

bool _isAlnum(String c) =>
    _isLetter(c) || (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57);

// ---------------------------------------------------------------------------
// Adaptive sizing — estimate the on-screen width so we can pick a font size
// ---------------------------------------------------------------------------

/// Picks a font size (logical px) for an expression so it fits [maxWidth]
/// without horizontal scrolling where possible, staying within
/// `[minFontSize, maxFontSize]`. Short expressions get the max size; longer ones
/// shrink toward the min. A [MathText] with `MathFit.scaleDown` remains the
/// exact safety net for the rare expression still too wide at the min.
double adaptiveMathFontSize({
  required String latex,
  required double maxWidth,
  required double minFontSize,
  required double maxFontSize,
}) {
  double em;
  try {
    em = estimateMathWidthEm(toDisplayLatex(latex));
  } catch (_) {
    // Malformed LaTeX must never crash layout — render at full size and let
    // MathText's own onErrorFallback show the raw string, exactly as before.
    return maxFontSize;
  }
  if (em <= 0 || maxWidth <= 0) return maxFontSize;
  // Average glyph advance ≈ 0.62 em at the math font; a size that "just fits"
  // then leaves a hair of breathing room instead of clipping on rounding.
  const advance = 0.62;
  final fit = maxWidth / (em * advance);
  if (fit >= maxFontSize) return maxFontSize;
  if (fit <= minFontSize) return minFontSize;
  return fit;
}

/// Rough width of a rendered expression in "em" units (character advances).
/// Deliberately approximate — [adaptiveMathFontSize] over-estimates safely
/// because [MathText]'s scale-down corrects any residual overflow. Accounts for
/// the two things that most break a naive character count: stacked fractions
/// (width is the *wider* of numerator/denominator, not their sum) and matrices
/// (width is the widest row).
double estimateMathWidthEm(String latex) {
  try {
    return _measureWidthEm(latex);
  } catch (_) {
    // Malformed LaTeX (e.g. a truncated `\frac{1}{2` from OCR) must never throw
    // from the sizing path — fall back to a plain glyph count. MathText's own
    // onErrorFallback then renders the raw string.
    return _plainEm(latex);
  }
}

double _measureWidthEm(String latex) {
  var s = latex;
  // The step-diff wraps the changed span in `\textcolor{#hex}{…}` — drop the
  // colour argument so its hex code isn't counted as glyphs (the inner span is
  // kept and measured normally).
  s = s.replaceAll(RegExp(r'\\textcolor\s*\{[^{}]*\}'), '');
  // Matrices: width is the widest row (cells joined by `&`, rows by `\\`).
  s = s.replaceAllMapped(
    RegExp(r'\\begin\{[a-zA-Z]*matrix\}(.*?)\\end\{[a-zA-Z]*matrix\}',
        dotAll: true),
    (m) {
      final rows = m.group(1)!.split(r'\\');
      var widest = 0.0;
      for (final row in rows) {
        var w = 0.0;
        for (final cell in row.split('&')) {
          w += _plainEm(_collapseFracs(cell)) + 1.4; // cell + column gap
        }
        if (w > widest) widest = w;
      }
      return 'X' * widest.round().clamp(1, 400);
    },
  );
  s = _collapseFracs(s);
  return _plainEm(s);
}

/// Replaces every `\frac{A}{B}` (and `\dfrac`/`\tfrac`) with whichever of A/B is
/// wider — a stacked fraction is only as wide as its widest line. Repeats until
/// none remain so nested fractions collapse correctly.
String _collapseFracs(String s) {
  final re = RegExp(r'\\[dt]?frac\s*\{');
  var guard = 0;
  while (guard++ < 200) {
    final m = re.firstMatch(s);
    if (m == null) break;
    final numOpen = m.end - 1; // the `{`
    final numEnd = _matchGroup(s, numOpen, '{', '}');
    var denOpen = numEnd + 1;
    while (denOpen < s.length && s[denOpen] == ' ') {
      denOpen++;
    }
    if (denOpen >= s.length || s[denOpen] != '{') break;
    final denEnd = _matchGroup(s, denOpen, '{', '}');
    final numer = s.substring(numOpen + 1, numEnd);
    final denom = s.substring(denOpen + 1, denEnd);
    final wider =
        _plainEm(_collapseFracs(numer)) >= _plainEm(_collapseFracs(denom))
            ? numer
            : denom;
    s = s.substring(0, m.start) + wider + s.substring(denEnd + 1);
  }
  return s;
}

/// Width of an expression with no top-level fractions, in em units.
double _plainEm(String latex) {
  var s = latex;
  // Big operators take horizontal room even before their operands.
  final big = RegExp(r'\\(int|iint|iiint|oint|sum|prod|lim|bigcup|bigcap)');
  final bigCount = big.allMatches(s).length;
  s = s.replaceAll(big, '');
  // Roots: keep the radicand, drop the command; add for the radical sign.
  final rootCount = RegExp(r'\\sqrt').allMatches(s).length;
  s = s.replaceAll(RegExp(r'\\sqrt\s*(\[[^\]]*\])?'), '');
  // Spacing / delimiters that add little or no width.
  s = s.replaceAll(RegExp(r'\\(left|right|,|;|!|:|quad|qquad| )'), '');
  // Named commands (\sin, \pi, \theta, \pm, \cdot, \times, \le …) ≈ one glyph.
  final cmdCount = RegExp(r'\\[a-zA-Z]+').allMatches(s).length;
  s = s.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');
  // Superscripts/subscripts render smaller — count their inner at 0.6.
  var scriptEm = 0.0;
  s = s.replaceAllMapped(RegExp(r'[\^_]\{([^{}]*)\}'), (m) {
    scriptEm += m.group(1)!.length * 0.6;
    return '';
  });
  s = s.replaceAllMapped(RegExp(r'[\^_].'), (m) {
    scriptEm += 0.6;
    return '';
  });
  // Structural characters that don't advance the pen.
  s = s.replaceAll(RegExp(r'[{}&\s]'), '');
  return s.length + scriptEm + bigCount * 1.8 + rootCount * 1.1 + cmdCount * 1.1;
}
