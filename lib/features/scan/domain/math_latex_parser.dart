import 'math_node.dart';
import 'math_templates.dart';

/// Turns LaTeX back into an editable [MathExpression].
///
/// This is what keeps "fix the equation we recognized" a *structured* edit: the
/// OCR result arrives as LaTeX, and without a parser the user would be handed
/// an opaque string instead of the same boxes-and-caret editor they get when
/// typing from scratch.
///
/// It is deliberately forgiving. Anything it can model becomes a template
/// ([MathTemplates]); anything it can't becomes a [MathAtom.raw] that keeps the
/// original LaTeX verbatim and is still drawn correctly by flutter_math. A hard
/// failure falls all the way back to per-character atoms — the one thing that
/// must never happen is losing part of what the user scanned.
class MathLatexParser {
  const MathLatexParser._();

  static MathExpression parse(String latex) {
    final trimmed = latex.trim();
    if (trimmed.isEmpty) return MathExpression();
    try {
      final parser = _Parser(_stripWrappers(trimmed));
      final expr = parser.parseSequence();
      // Anything left over means we bailed mid-string; keep it verbatim rather
      // than silently truncating the user's problem.
      if (!parser.atEnd) {
        expr.nodes.add(MathAtom.raw(parser.rest));
      }
      return expr;
    } catch (_) {
      return MathExpression.chars(trimmed);
    }
  }

  /// Drops display-math fences the recognizer sometimes returns.
  static String _stripWrappers(String s) {
    var out = s;
    for (final pair in const [
      [r'$$', r'$$'],
      [r'\[', r'\]'],
      [r'\(', r'\)'],
      [r'$', r'$'],
    ]) {
      if (out.length > pair[0].length + pair[1].length &&
          out.startsWith(pair[0]) &&
          out.endsWith(pair[1])) {
        out = out.substring(pair[0].length, out.length - pair[1].length).trim();
      }
    }
    return out;
  }
}

/// LaTeX commands that map to a single glyph.
const Map<String, String> _symbolGlyphs = {
  'pi': 'π', 'theta': 'θ', 'alpha': 'α', 'beta': 'β', 'gamma': 'γ',
  'delta': 'δ', 'Delta': 'Δ', 'epsilon': 'ε', 'lambda': 'λ', 'mu': 'μ',
  'rho': 'ρ', 'phi': 'φ', 'varphi': 'φ', 'sigma': 'σ', 'Sigma': 'Σ',
  'omega': 'ω', 'Omega': 'Ω', 'tau': 'τ', 'psi': 'ψ', 'chi': 'χ',
  'infty': '∞', 'cdot': '·', 'times': '×', 'div': '÷', 'pm': '±', 'mp': '∓',
  'le': '≤', 'leq': '≤', 'ge': '≥', 'geq': '≥', 'ne': '≠', 'neq': '≠',
  'approx': '≈', 'equiv': '≡', 'propto': '∝', 'to': '→', 'rightarrow': '→',
  'Rightarrow': '⇒', 'leftarrow': '←', 'partial': '∂', 'nabla': '∇',
  'int': '∫', 'iint': '∬', 'oint': '∮', 'sum': '∑', 'prod': '∏',
  'dots': '…', 'ldots': '…', 'cdots': '⋯', 'circ': '∘', 'degree': '°',
  'angle': '∠', 'triangle': '△', 'perp': '⊥', 'parallel': '∥',
  'in': '∈', 'notin': '∉', 'cup': '∪', 'cap': '∩', 'subset': '⊂',
  'forall': '∀', 'exists': '∃', 'emptyset': '∅', 'therefore': '∴',
  'prime': '′', 'ell': 'ℓ', 'Re': 'ℜ', 'Im': 'ℑ',
};

/// Backslash-escaped literals — `\%`, `\{` …
const Map<String, String> _escapedLiterals = {
  '%': '%', r'$': r'$', '#': '#', '&': '&', '_': '_', '{': '{', '}': '}',
};

/// Zero-width spacing commands, dropped on the way in.
const Set<String> _spacingCommands = {',', ';', '!', ':', ' ', 'quad', 'qquad'};

class _Parser {
  _Parser(this.src);

  final String src;
  int i = 0;

  bool get atEnd => i >= src.length;
  String get cur => src[i];
  String get rest => src.substring(i);

  /// Parses nodes until the end of input or a terminator that belongs to the
  /// caller (`}`, `&`, `\\`, `\right`, `\end`) — which is left unconsumed.
  MathExpression parseSequence() {
    final nodes = <MathNode>[];
    while (true) {
      _skipWhitespace();
      if (atEnd) break;
      final c = cur;
      if (c == '}' || c == '&') break;
      if (c == r'\') {
        if (_startsWith(r'\\')) break;
        final name = _peekCommandName();
        if (name == 'right' || name == 'end') break;
      }
      if (c == '^' || c == '_') {
        i++;
        final arg = _readArgExpression();
        final base = nodes.isEmpty
            ? MathExpression()
            : MathExpression([nodes.removeLast()]);
        nodes.add(_scriptNode(base, arg, raised: c == '^'));
        continue;
      }
      final node = _parseUnit();
      if (node != null) nodes.add(node);
    }
    return MathExpression(nodes);
  }

  MathNode? _parseUnit() {
    final c = cur;
    if (c == r'\') return _parseCommand();
    if (c == '{') {
      // A bare group is pure grouping — splice its contents in, don't nest.
      i++;
      final inner = parseSequence();
      if (!atEnd && cur == '}') i++;
      if (inner.nodes.length == 1) return inner.nodes.first;
      if (inner.isEmpty) return null;
      return MathTemplateNode(MathTemplates.paren, [inner]);
    }
    if (c == '(') {
      final close = _findMatching(i, '(', ')');
      if (close != null) {
        final inner = MathLatexParser.parse(src.substring(i + 1, close));
        i = close + 1;
        return MathTemplateNode(MathTemplates.paren, [inner]);
      }
    }
    if (c == '[') {
      final close = _findMatching(i, '[', ']');
      if (close != null) {
        final inner = MathLatexParser.parse(src.substring(i + 1, close));
        i = close + 1;
        return MathTemplateNode(MathTemplates.bracket, [inner]);
      }
    }
    i++;
    return MathAtom.char(c);
  }

  // -- Commands -------------------------------------------------------------

  MathNode? _parseCommand() {
    i++; // past the backslash
    if (atEnd) return MathAtom.char('\\');

    final name = _readCommandName();
    if (name == null) {
      final ch = src[i];
      i++;
      if (_spacingCommands.contains(ch)) return null;
      final literal = _escapedLiterals[ch];
      if (literal != null) {
        return MathAtom(latex: '\\$ch', display: literal);
      }
      return MathAtom.raw('\\$ch');
    }
    if (_spacingCommands.contains(name)) return null;

    switch (name) {
      case 'frac':
      case 'dfrac':
      case 'tfrac':
        return MathTemplateNode(
          MathTemplates.frac,
          [_readArgExpression(), _readArgExpression()],
        );
      case 'binom':
      case 'dbinom':
        return MathTemplateNode(
          MathTemplates.binomial,
          [_readArgExpression(), _readArgExpression()],
        );
      case 'sqrt':
        return _parseSqrt();
      case 'overline':
      case 'bar':
        return MathTemplateNode(MathTemplates.conjugate, [_readArgExpression()]);
      case 'left':
        return _parseLeftRight();
      case 'begin':
        return _parseEnvironment();
      case 'lim':
        return _parseLimit();
      case 'log':
        return _parseLog();
      case 'operatorname':
        return _parseOperatorName();
      case 'text':
      case 'mathrm':
      case 'mathit':
      case 'mathbf':
        final body = _readRawArg();
        return MathAtom(
          latex: '\\$name{$body}',
          display: body,
          render: MathAtomRender.operatorName,
        );
    }

    final fn = MathTemplates.functions[name];
    if (fn != null) {
      final arg = _tryReadParenArg();
      if (arg != null) return MathTemplateNode(fn, [arg]);
      return MathAtom.operatorName(name);
    }

    final glyph = _symbolGlyphs[name];
    if (glyph != null) {
      return MathAtom(latex: '\\$name ', display: glyph);
    }
    return MathAtom.raw('\\$name ');
  }

  MathNode _parseSqrt() {
    _skipWhitespace();
    if (!atEnd && cur == '[') {
      final close = _findMatching(i, '[', ']');
      if (close != null) {
        final indexLatex = src.substring(i + 1, close).trim();
        i = close + 1;
        final radicand = _readArgExpression();
        if (indexLatex == '3') {
          return MathTemplateNode(MathTemplates.cbrt, [radicand]);
        }
        return MathTemplateNode(
          MathTemplates.nthroot,
          [MathLatexParser.parse(indexLatex), radicand],
        );
      }
    }
    return MathTemplateNode(MathTemplates.sqrt, [_readArgExpression()]);
  }

  MathNode _parseLeftRight() {
    final open = _readDelimiter();
    final inner = parseSequence();
    if (_peekCommandName() == 'right') {
      _consumeCommandName();
      _readDelimiter();
    }
    return switch (open) {
      '|' => MathTemplateNode(MathTemplates.abs, [inner]),
      '[' => MathTemplateNode(MathTemplates.bracket, [inner]),
      '{' => MathTemplateNode(MathTemplates.braceSet, [inner]),
      _ => MathTemplateNode(MathTemplates.paren, [inner]),
    };
  }

  /// `\begin{bmatrix} a & b \\ c & d \end{bmatrix}` and friends.
  MathNode _parseEnvironment() {
    final env = _readRawArg();
    final rows = <List<MathExpression>>[];
    var row = <MathExpression>[];
    while (!atEnd) {
      row.add(parseSequence());
      _skipWhitespace();
      if (atEnd) break;
      if (cur == '&') {
        i++;
        continue;
      }
      if (_startsWith(r'\\')) {
        i += 2;
        rows.add(row);
        row = <MathExpression>[];
        continue;
      }
      if (_peekCommandName() == 'end') {
        _consumeCommandName();
        _readRawArg();
        break;
      }
      break;
    }
    if (row.isNotEmpty) rows.add(row);

    final isDeterminant = env == 'vmatrix';
    final cols = rows.isEmpty ? 0 : rows.first.length;
    final rectangular = rows.every((r) => r.length == cols);
    if (rectangular) {
      if (rows.length == 2 && cols == 2) {
        return MathTemplateNode(
          isDeterminant
              ? MathTemplates.determinant2x2
              : MathTemplates.matrix2x2,
          [...rows[0], ...rows[1]],
        );
      }
      if (rows.length == 3 && cols == 3 && !isDeterminant) {
        return MathTemplateNode(
          MathTemplates.matrix3x3,
          [...rows[0], ...rows[1], ...rows[2]],
        );
      }
      if (rows.length == 2 && cols == 1 && !isDeterminant) {
        return MathTemplateNode(MathTemplates.vector2, [...rows[0], ...rows[1]]);
      }
    }
    // A shape we don't have a template for — keep the LaTeX exactly.
    final body = rows
        .map((r) => r.map((c) => c.toLatex()).join(' & '))
        .join(r' \\ ');
    return MathAtom.raw('\\begin{$env}$body\\end{$env}');
  }

  /// `\lim_{x \to a}`, including the one-sided `a^{+}` / `a^{-}` forms.
  MathNode _parseLimit() {
    final save = i;
    _skipWhitespace();
    if (atEnd || cur != '_') {
      i = save;
      return MathAtom.operatorName('lim');
    }
    i++;
    final raw = _readRawArg();
    final arrow = _splitOnArrow(raw);
    if (arrow == null) {
      i = save;
      return MathAtom.operatorName('lim');
    }
    var target = arrow[1].trim();
    var template = MathTemplates.limit;
    for (final entry in const {
      '^{+}': 'right', '^+': 'right', '^{-}': 'left', '^-': 'left',
    }.entries) {
      if (target.endsWith(entry.key)) {
        target = target.substring(0, target.length - entry.key.length);
        template = entry.value == 'right'
            ? MathTemplates.limitRight
            : MathTemplates.limitLeft;
        break;
      }
    }
    return MathTemplateNode(template, [
      MathLatexParser.parse(arrow[0]),
      MathLatexParser.parse(target),
    ]);
  }

  /// Splits `x \to a` into its two sides, or returns null when there's no arrow.
  List<String>? _splitOnArrow(String raw) {
    for (final arrow in const [r'\to', r'\rightarrow', '→']) {
      final at = raw.indexOf(arrow);
      if (at >= 0) {
        return [raw.substring(0, at), raw.substring(at + arrow.length)];
      }
    }
    return null;
  }

  MathNode _parseLog() {
    _skipWhitespace();
    MathExpression? base;
    if (!atEnd && cur == '_') {
      i++;
      base = _readArgExpression();
    }
    final arg = _tryReadParenArg();
    if (base != null) {
      final baseLatex = base.toLatex().trim();
      if (arg != null && baseLatex == '10') {
        return MathTemplateNode(MathTemplates.log10, [arg]);
      }
      if (arg != null && baseLatex == '2') {
        return MathTemplateNode(MathTemplates.log2, [arg]);
      }
      return MathTemplateNode(
        MathTemplates.logBase,
        [base, arg ?? MathExpression()],
      );
    }
    if (arg != null) {
      return MathTemplateNode(MathTemplates.functions['log']!, [arg]);
    }
    return MathAtom.operatorName('log');
  }

  MathNode _parseOperatorName() {
    final name = _readRawArg();
    final fn = MathTemplates.functions[name];
    if (fn != null) {
      final arg = _tryReadParenArg();
      if (arg != null) return MathTemplateNode(fn, [arg]);
    }
    return MathAtom.operatorName(name);
  }

  // -- Scripts --------------------------------------------------------------

  MathNode _scriptNode(
    MathExpression base,
    MathExpression script, {
    required bool raised,
  }) {
    // `x_1^2` and `\int_a^b` reach here as two scripts applied to the same
    // base. Fold them into one node so the two limits stack at one height
    // instead of nesting a power around a subscript.
    final combined = _combineScripts(base, script, raised: raised);
    if (combined != null) return combined;
    if (!raised) {
      return MathTemplateNode(MathTemplates.subscript, [base, script]);
    }
    final latex = script.toLatex().trim();
    return switch (latex) {
      '2' => MathTemplateNode(MathTemplates.square, [base]),
      '3' => MathTemplateNode(MathTemplates.cube, [base]),
      r'\circ' || r'\circ ' || '°' =>
        MathTemplateNode(MathTemplates.degrees, [base]),
      _ => MathTemplateNode(MathTemplates.power, [base, script]),
    };
  }

  /// Merges a script onto a base that already carries the other one.
  MathTemplateNode? _combineScripts(
    MathExpression base,
    MathExpression script, {
    required bool raised,
  }) {
    if (base.nodes.length != 1) return null;
    final only = base.nodes.first;
    if (only is! MathTemplateNode) return null;
    final id = only.template.id;

    if (raised && id == MathTemplates.subscript.id) {
      return MathTemplateNode(
        MathTemplates.subsup,
        [only.slots[0], only.slots[1], script],
      );
    }
    if (raised) return null;
    return switch (id) {
      'power' => MathTemplateNode(
          MathTemplates.subsup,
          [only.slots[0], script, only.slots[1]],
        ),
      'square' => MathTemplateNode(
          MathTemplates.subsup,
          [only.slots[0], script, MathExpression.chars('2')],
        ),
      'cube' => MathTemplateNode(
          MathTemplates.subsup,
          [only.slots[0], script, MathExpression.chars('3')],
        ),
      _ => null,
    };
  }

  // -- Low-level readers ----------------------------------------------------

  void _skipWhitespace() {
    while (!atEnd && (cur == ' ' || cur == '\n' || cur == '\t')) {
      i++;
    }
  }

  bool _startsWith(String s) => src.startsWith(s, i);

  /// The command name at the caret without consuming it (`null` if not on one).
  String? _peekCommandName() {
    if (atEnd || cur != r'\') return null;
    final match = RegExp(r'^\\([a-zA-Z]+)').firstMatch(src.substring(i));
    return match?.group(1);
  }

  void _consumeCommandName() {
    final name = _peekCommandName();
    if (name != null) i += name.length + 1;
  }

  /// Reads the letters of a command whose backslash is already consumed.
  String? _readCommandName() {
    final match = RegExp(r'^[a-zA-Z]+').firstMatch(src.substring(i));
    if (match == null) return null;
    final name = match.group(0)!;
    i += name.length;
    return name;
  }

  /// The delimiter after `\left` / `\right` — `(`, `|`, `\{`, `.` …
  String _readDelimiter() {
    _skipWhitespace();
    if (atEnd) return '.';
    if (cur == r'\') {
      i++;
      if (atEnd) return '.';
      final name = _readCommandName();
      if (name != null) return _symbolGlyphs[name] ?? name;
      final ch = src[i];
      i++;
      return ch;
    }
    final ch = cur;
    i++;
    return ch;
  }

  /// One LaTeX argument as a parsed expression — `{…}` or a single token.
  MathExpression _readArgExpression() {
    _skipWhitespace();
    if (atEnd) return MathExpression();
    if (cur == '{') {
      i++;
      final inner = parseSequence();
      if (!atEnd && cur == '}') i++;
      return inner;
    }
    if (cur == r'\') {
      final node = _parseCommand();
      return MathExpression(node == null ? [] : [node]);
    }
    final ch = cur;
    i++;
    return MathExpression([MathAtom.char(ch)]);
  }

  /// One LaTeX argument as its raw source text.
  String _readRawArg() {
    _skipWhitespace();
    if (atEnd) return '';
    if (cur == '{') {
      final close = _findMatching(i, '{', '}');
      if (close == null) return '';
      final body = src.substring(i + 1, close);
      i = close + 1;
      return body;
    }
    final ch = cur;
    i++;
    return ch;
  }

  /// A parenthesised function argument, if one follows. Restores the position
  /// when it doesn't, so `\sin` alone stays a bare operator name.
  MathExpression? _tryReadParenArg() {
    final save = i;
    _skipWhitespace();
    if (_peekCommandName() == 'left') {
      _consumeCommandName();
      final open = _readDelimiter();
      if (open != '(') {
        i = save;
        return null;
      }
      final inner = parseSequence();
      if (_peekCommandName() == 'right') {
        _consumeCommandName();
        _readDelimiter();
      }
      return inner;
    }
    if (!atEnd && cur == '(') {
      final close = _findMatching(i, '(', ')');
      if (close != null) {
        final inner = MathLatexParser.parse(src.substring(i + 1, close));
        i = close + 1;
        return inner;
      }
    }
    i = save;
    return null;
  }

  /// Index of the [close] that matches the [open] at [from], or null.
  int? _findMatching(int from, String open, String close) {
    var depth = 0;
    for (var j = from; j < src.length; j++) {
      final c = src[j];
      if (c == r'\') {
        j++; // skip the escaped character / command letter
        continue;
      }
      if (c == open) {
        depth++;
      } else if (c == close) {
        depth--;
        if (depth == 0) return j;
      }
    }
    return null;
  }
}
