/// Presentation-only LaTeX helpers for the result screen.
///
/// These reshape how math is *displayed* and estimate its on-screen width so the
/// answer/steps can be sized adaptively. They NEVER change a mathematical value:
/// the golden rule (the server computes and verifies the answer) is untouched —
/// this only affects typesetting. `\frac`-folding turns an inline `a/b` into a
/// stacked fraction; the number it represents is identical.
///
/// Two of them exist for one reason: **the student must never be shown LaTeX
/// source.** [parseProblemStatement] splits a recognized problem into the prose
/// and the maths the worksheet actually had, and [toReadableMath] is the
/// last-resort rendering — plain, readable, unicode maths — for when
/// `flutter_math` can't typeset a string. Neither is ever allowed to throw.
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
// Statement parsing — prose is prose, maths is maths, and neither is source
// ---------------------------------------------------------------------------

/// What one line of a recognized problem statement is.
enum StatementKind {
  /// Instructional wording — "Solve the equation", "Give your answer in surd
  /// form". Rendered as ordinary text.
  prose,

  /// LaTeX to be typeset by `flutter_math`.
  math,
}

/// One line of a recognized problem statement — see [parseProblemStatement].
class StatementLine {
  const StatementLine.prose(this.content) : kind = StatementKind.prose;
  const StatementLine.math(this.content) : kind = StatementKind.math;

  final StatementKind kind;

  /// Plain text for [StatementKind.prose]; LaTeX for [StatementKind.math].
  final String content;

  bool get isMath => kind == StatementKind.math;

  @override
  bool operator ==(Object other) =>
      other is StatementLine && other.kind == kind && other.content == content;

  @override
  int get hashCode => Object.hash(kind, content);

  @override
  String toString() => '${kind.name}($content)';
}

/// Splits a recognized problem into the lines a worksheet would have had.
///
/// The recognizer returns one LaTeX string for the whole problem, and it may
/// carry the instruction with it:
///
///     \text{Solve the equation} \\ 9^{4x-3} = \frac{1}{3\sqrt{3}}
///
/// Rendered as a single expression that is at best ugly and at worst untypesettable
/// (`flutter_math` has no line break outside an alignment environment), which is
/// how raw backslashes ended up in front of students. So: break on the LaTeX
/// line break, hoist a leading/trailing `\text{…}` run out into prose, and hand
/// back what each line really is.
///
/// Row breaks *inside* a matrix or a `cases` block belong to that environment
/// and are left alone. Never throws — a string it can't make sense of comes back
/// as a single math line, exactly as before.
List<StatementLine> parseProblemStatement(String latex) {
  try {
    final out = <StatementLine>[];
    for (final raw in _splitStatementLines(_stripMathDelimiters(latex))) {
      if (raw.trim().isEmpty) continue;
      out.addAll(_splitProseAndMath(raw.trim()));
    }
    if (out.isNotEmpty) return out;
  } catch (_) {
    // fall through
  }
  final t = latex.trim();
  return t.isEmpty ? const [] : [StatementLine.math(t)];
}

/// Removes the math-mode delimiters some recognizers wrap their output in
/// (`$…$`, `$$…$$`, `\[…\]`, `\(…\)`), which `flutter_math` renders literally.
String _stripMathDelimiters(String s) {
  var t = s.trim();
  for (var guard = 0; guard < 4; guard++) {
    final pair = _wrappingDelimiter(t);
    if (pair == null) break;
    t = t.substring(pair.$1.length, t.length - pair.$2.length).trim();
  }
  return t;
}

(String, String)? _wrappingDelimiter(String t) {
  const pairs = [(r'$$', r'$$'), (r'\[', r'\]'), (r'\(', r'\)'), (r'$', r'$')];
  for (final (open, close) in pairs) {
    if (t.length <= open.length + close.length) continue;
    if (!t.startsWith(open) || !t.endsWith(close)) continue;
    // Only when they WRAP: `$a$ = $b$` is not one delimited expression.
    final inner = t.substring(open.length, t.length - close.length);
    if (inner.contains(open) || inner.contains(close)) continue;
    return (open, close);
  }
  return null;
}

/// Splits on a top-level LaTeX line break (`\\`, `\newline`, `\cr`). Breaks
/// inside a `{…}` group or a `\begin…\end` environment are that construct's own
/// and stay put.
List<String> _splitStatementLines(String s) {
  final lines = <String>[];
  final buf = StringBuffer();
  var depth = 0;
  var env = 0;
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == '{') {
      depth++;
      buf.write(c);
      i++;
      continue;
    }
    if (c == '}') {
      if (depth > 0) depth--;
      buf.write(c);
      i++;
      continue;
    }
    if (c != r'\') {
      buf.write(c);
      i++;
      continue;
    }
    final boundary = _environmentAt(s, i);
    if (boundary != null) {
      env += boundary.$1;
      buf.write(s.substring(i, boundary.$2));
      i = boundary.$2;
      continue;
    }
    final brk = _lineBreakAt(s, i);
    if (brk != null) {
      if (depth == 0 && env <= 0) {
        lines.add(buf.toString());
        buf.clear();
      } else {
        buf.write(s.substring(i, brk));
      }
      i = brk;
      continue;
    }
    // Any other command — copy it whole so its letters can't be re-read here.
    var j = i + 1;
    if (j < s.length && _isLetter(s[j])) {
      while (j < s.length && _isLetter(s[j])) {
        j++;
      }
    } else if (j < s.length) {
      j++;
    }
    buf.write(s.substring(i, j));
    i = j;
  }
  lines.add(buf.toString());
  return lines;
}

final _envBoundary = RegExp(r'\\(begin|end)\s*\{[^{}]*\}');

/// `(+1 | -1, end index)` when a `\begin{…}`/`\end{…}` starts at [i].
(int, int)? _environmentAt(String s, int i) {
  final m = _envBoundary.matchAsPrefix(s, i);
  if (m == null) return null;
  return (m.group(1) == 'begin' ? 1 : -1, m.end);
}

final _lineBreak = RegExp(r'(\\\\|\\newline|\\cr)(?![a-zA-Z])\s*(\[[^\]]*\])?');

/// The index just past a LaTeX line break starting at [i], or null.
int? _lineBreakAt(String s, int i) => _lineBreak.matchAsPrefix(s, i)?.end;

final _textMacro =
    RegExp(r'\\(?:textrm|textbf|textit|textsf|textnormal|text|mbox)\s*\{');

/// Hoists the instruction out of the maths: a `\text{…}` run at the start of a
/// line becomes prose ABOVE the equation, one at the end becomes prose below it.
/// A `\text{…}` in the middle ("… where x > 0") is part of the expression and
/// stays in it — `flutter_math` sets that correctly.
List<StatementLine> _splitProseAndMath(String line) {
  final before = <StatementLine>[];
  final after = <StatementLine>[];
  var s = line.trim();

  while (true) {
    final m = _textMacro.matchAsPrefix(s);
    if (m == null) break;
    final end = _matchGroup(s, m.end - 1, '{', '}');
    final prose = _proseText(s.substring(m.end, end));
    if (prose.isNotEmpty) before.add(StatementLine.prose(prose));
    s = s.substring(end + 1).trim();
  }

  while (true) {
    final start = _trailingTextMacro(s);
    if (start == null) break;
    final m = _textMacro.matchAsPrefix(s, start)!;
    final end = _matchGroup(s, m.end - 1, '{', '}');
    final prose = _proseText(s.substring(m.end, end));
    if (prose.isNotEmpty) after.insert(0, StatementLine.prose(prose));
    s = s.substring(0, start).trim();
  }

  return [
    ...before,
    if (s.isNotEmpty) StatementLine.math(s),
    ...after,
  ];
}

/// Start index of the first `\text{…}` whose group runs to the end of [s].
int? _trailingTextMacro(String s) {
  for (final m in _textMacro.allMatches(s)) {
    final end = _matchGroup(s, m.end - 1, '{', '}');
    if (s.substring(end + 1).trim().isEmpty) return m.start;
  }
  return null;
}

/// Prose from the inside of a `\text{…}`. Anything still LaTeX in there (a
/// spacing command, an escaped `%`) goes through [toReadableMath] so no
/// backslash can survive into the sentence.
String _proseText(String inner) {
  final t = inner.contains(r'\') ? toReadableMath(inner) : inner;
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ---------------------------------------------------------------------------
// The readable fallback — what a student sees when typesetting fails
// ---------------------------------------------------------------------------

/// Renders LaTeX as plain, readable unicode maths: `\frac{1}{3\sqrt{3}}` becomes
/// `1/(3√(3))`, `9^{4x-3}` becomes `9^(4x-3)`, `\theta` becomes `θ`.
///
/// This is the fallback behind every [MathText]. It is not typesetting and does
/// not pretend to be — its one promise is that a student never sees a backslash,
/// because `\frac` on screen is our bug leaking out, not information. Never
/// throws: the worst case strips the markup and returns the rest.
String toReadableMath(String latex) {
  try {
    return _collapseSpaces(_readable(latex));
  } catch (_) {
    return _collapseSpaces(_stripCommands(latex));
  }
}

String _readable(String src) {
  var s = src;
  // Escapes first — `\%` is a percent sign, not a command.
  s = s.replaceAllMapped(RegExp(r'\\([%$&#])'), (m) => m.group(1)!);
  s = s.replaceAll(r'\{', '(').replaceAll(r'\}', ')');
  // Degrees are written as a superscript circle; read them as one glyph.
  s = s.replaceAll(RegExp(r'\^\s*\{?\s*\\circ\s*\}?'), '°');
  // Spacing and sizing carry no meaning here.
  s = s.replaceAll(RegExp(r'\\(?:displaystyle|textstyle|limits|nolimits)\b'), ' ');
  s = s.replaceAll(
      RegExp(r'\\(?:left|right|bigg?|Bigg?)(?![a-zA-Z])'), '');
  s = s.replaceAll(RegExp(r'\\(?:quad|qquad)\b'), '  ');
  // The thin-space escapes — but never the second half of a `\\` line break,
  // which the environments below still need to find its rows by.
  s = s.replaceAll(RegExp(r'(?<!\\)\\[,;:!> ]'), ' ');
  s = s.replaceAll('~', ' ');
  s = _readableEnvironments(s);
  // Any break left once the environments are folded — a statement rendered
  // whole rather than through [parseProblemStatement] — reads as a gap.
  s = s.replaceAll(RegExp(r'\\\\|\\(?:newline|cr)(?![a-zA-Z])'), '  ');
  s = _readableArguments(s);
  s = _readableSymbols(s);
  s = _readableScripts(s);
  s = s.replaceAll(RegExp(r'[{}]'), '');
  // Relations breathe: LaTeX sets that spacing itself, so the source often has
  // none (`=\frac{1}{2}`), and `x =1/2` reads worse than it needs to.
  s = s.replaceAllMapped(
      RegExp(r'\s*([=≠≤≥≈<>])\s*'), (m) => ' ${m.group(1)} ');
  return _stripCommands(s);
}

/// Matrices, `cases` and aligned blocks as one line: rows separated by `;`,
/// cells by `,` (a matrix) or a space (everything else).
String _readableEnvironments(String s) {
  final re = RegExp(
    r'\\begin\s*\{([a-zA-Z*]+)\}(?:\s*\{[^{}]*\})?([\s\S]*?)\\end\s*\{\1\}',
  );
  var out = s;
  for (var guard = 0; guard < 20; guard++) {
    final m = re.firstMatch(out);
    if (m == null) break;
    final name = m.group(1)!;
    final matrix = name.toLowerCase().contains('matrix');
    final rows = m
        .group(2)!
        .split(RegExp(r'\\\\'))
        .map((r) => r.split('&').map((c) => c.trim()).where((c) => c.isNotEmpty))
        .map((cells) => cells.join(matrix ? ', ' : ' '))
        .where((r) => r.isNotEmpty)
        .toList();
    final body = rows.join('; ');
    out = out.replaceRange(
        m.start, m.end, matrix ? '[$body]' : (rows.length > 1 ? '{$body}' : body));
  }
  return out;
}

/// The commands that take braced arguments — the ones a naive strip would
/// mangle into nonsense (`\frac{1}{2}` → `12`).
String _readableArguments(String s) {
  final head = RegExp(
    r'\\(dfrac|tfrac|frac|cfrac|sqrt|binom|operatorname|overline|underline'
    r'|overrightarrow|vec|hat|bar|tilde|boldsymbol|mathbf|mathrm|mathit|mathbb'
    r'|mathcal|text|textrm|textbf|textit|textsf|textnormal|mbox)\s*',
  );
  var out = s;
  for (var guard = 0; guard < 400; guard++) {
    final m = head.firstMatch(out);
    if (m == null) break;
    var i = m.end;
    String? optional;
    if (i < out.length && out[i] == '[') {
      final close = out.indexOf(']', i);
      if (close < 0) break;
      optional = out.substring(i + 1, close);
      i = close + 1;
    }
    final args = <String>[];
    final wanted = switch (m.group(1)!) {
      'frac' || 'dfrac' || 'tfrac' || 'cfrac' || 'binom' => 2,
      _ => 1,
    };
    var ok = true;
    while (args.length < wanted) {
      while (i < out.length && out[i] == ' ') {
        i++;
      }
      if (i >= out.length) {
        ok = false;
        break;
      }
      if (out[i] == '{') {
        final end = _matchGroup(out, i, '{', '}');
        args.add(out.substring(i + 1, end));
        i = end + 1;
      } else {
        // `\sqrt x` — a single token is a legal argument.
        final start = i;
        if (out[i] == r'\') {
          i++;
          while (i < out.length && _isLetter(out[i])) {
            i++;
          }
        } else {
          i++;
        }
        args.add(out.substring(start, i));
      }
    }
    if (!ok) break;
    out = out.replaceRange(
        m.start, i, _buildReadable(m.group(1)!, args, optional));
  }
  return out;
}

String _buildReadable(String name, List<String> args, String? optional) {
  switch (name) {
    case 'frac':
    case 'dfrac':
    case 'tfrac':
    case 'cfrac':
      return '${_operand(args[0])}/${_operand(args[1])}';
    case 'sqrt':
      if (optional == null) return '√${_operand(args[0])}';
      // A cube/fourth root reads best as an explicit power.
      return '${_operand(args[0])}^(1/${optional.trim()})';
    case 'binom':
      return 'C(${args[0]}, ${args[1]})';
    default:
      // Fonts, accents and `\text` all leave their content behind.
      return args[0];
  }
}

/// Parenthesises an operand unless it is already a single unambiguous one.
String _operand(String arg) {
  final t = arg.trim();
  if (t.isEmpty) return '()';
  if (RegExp(r'^[A-Za-z0-9.°]+$').hasMatch(t)) return t;
  if (t.startsWith('(') && t.endsWith(')')) return t;
  return '($t)';
}

/// Every remaining `\command` → the symbol it stands for, or its bare name
/// (`\sin` → `sin`), so nothing keeps its backslash.
String _readableSymbols(String s) => s.replaceAllMapped(
      RegExp(r'\\([a-zA-Z]+)'),
      (m) => _symbols[m.group(1)!] ?? m.group(1)!,
    );

String _readableScripts(String s) {
  var t = s;
  t = t.replaceAllMapped(
      RegExp(r'\^\s*\{([^{}]*)\}'), (m) => _script(m.group(1)!, sup: true));
  t = t.replaceAllMapped(
      RegExp(r'_\s*\{([^{}]*)\}'), (m) => _script(m.group(1)!, sup: false));
  t = t.replaceAllMapped(
      RegExp(r'\^\s*([A-Za-z0-9°])'), (m) => _script(m.group(1)!, sup: true));
  t = t.replaceAllMapped(
      RegExp(r'_\s*([A-Za-z0-9])'), (m) => _script(m.group(1)!, sup: false));
  return t;
}

/// A script as unicode when every character has a form (`x^2` → `x²`), and as
/// an explicit `^(…)` when it doesn't — never as `^{…}`.
String _script(String inner, {required bool sup}) {
  final t = inner.trim();
  if (t.isEmpty) return '';
  final map = sup ? _superscripts : _subscripts;
  if (t.split('').every(map.containsKey)) {
    return t.split('').map((c) => map[c]!).join();
  }
  final mark = sup ? '^' : '_';
  return t.length == 1 ? '$mark$t' : '$mark($t)';
}

/// Last resort: drop every backslash, keeping the letters after it. Ugly, but
/// `frac` is at least a word and not obviously broken punctuation.
String _stripCommands(String s) =>
    s.replaceAllMapped(RegExp(r'\\([a-zA-Z]+)?'), (m) => m.group(1) ?? '');

String _collapseSpaces(String s) =>
    s.replaceAll(RegExp(r'[ \t]+'), ' ').trim();

const _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴',
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '−': '⁻', '(': '⁽', ')': '⁾', 'n': 'ⁿ',
};

const _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄',
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '−': '₋', '(': '₍', ')': '₎',
};

/// LaTeX commands that stand for a single glyph. Anything absent keeps its name
/// (`\sin` reads perfectly well as `sin`).
const _symbols = {
  // Greek
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ', 'epsilon': 'ε',
  'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η', 'theta': 'θ', 'vartheta': 'ϑ',
  'iota': 'ι', 'kappa': 'κ', 'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ',
  'pi': 'π', 'varpi': 'ϖ', 'rho': 'ρ', 'varrho': 'ϱ', 'sigma': 'σ',
  'varsigma': 'ς', 'tau': 'τ', 'upsilon': 'υ', 'phi': 'φ', 'varphi': 'φ',
  'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ',
  'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ', 'Phi': 'Φ', 'Psi': 'Ψ',
  'Omega': 'Ω',
  // Operators and relations
  'times': '×', 'div': '÷', 'cdot': '·', 'cdots': '⋯', 'ldots': '…',
  'dots': '…', 'vdots': '⋮', 'ddots': '⋱', 'pm': '±', 'mp': '∓',
  'leq': '≤', 'le': '≤', 'geq': '≥', 'ge': '≥', 'neq': '≠', 'ne': '≠',
  'approx': '≈', 'equiv': '≡', 'sim': '∼', 'simeq': '≃', 'cong': '≅',
  'propto': '∝', 'll': '≪', 'gg': '≫',
  // Big operators and calculus
  'int': '∫', 'iint': '∬', 'iiint': '∭', 'oint': '∮', 'sum': '∑',
  'prod': '∏', 'partial': '∂', 'nabla': '∇', 'infty': '∞', 'infin': '∞',
  'prime': '′', 'circ': '°', 'degree': '°', 'angle': '∠',
  // Sets and logic
  'in': '∈', 'notin': '∉', 'ni': '∋', 'subset': '⊂', 'subseteq': '⊆',
  'supset': '⊃', 'supseteq': '⊇', 'cup': '∪', 'cap': '∩',
  'emptyset': '∅', 'varnothing': '∅', 'forall': '∀', 'exists': '∃',
  'neg': '¬', 'land': '∧', 'lor': '∨', 'therefore': '∴', 'because': '∵',
  // Arrows
  'to': '→', 'rightarrow': '→', 'longrightarrow': '⟶', 'leftarrow': '←',
  'longleftarrow': '⟵', 'leftrightarrow': '↔', 'Rightarrow': '⇒',
  'Leftarrow': '⇐', 'Leftrightarrow': '⇔', 'mapsto': '↦', 'implies': '⇒',
  'iff': '⇔',
  // Delimiters that survive as glyphs
  'lvert': '|', 'rvert': '|', 'lVert': '‖', 'rVert': '‖', 'vert': '|',
  'Vert': '‖', 'langle': '⟨', 'rangle': '⟩', 'perp': '⊥', 'parallel': '∥',
  'star': '⋆', 'ast': '*', 'bullet': '•', 'oplus': '⊕', 'otimes': '⊗',
};

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
