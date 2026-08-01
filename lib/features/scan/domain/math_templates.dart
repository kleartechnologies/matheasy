/// The catalogue of structured math templates — every keyboard key that opens
/// dashed placeholder boxes, plus the visual form each one takes.
///
/// A template declares three things and nothing else:
///
/// * how many **slots** (editable child expressions) it owns,
/// * a [MathPart] tree describing **how it looks** — a pure, Flutter-free
///   description that both the field renderer and the key faces walk, so a key
///   face is literally a miniature of what tapping it produces, and
/// * how to turn its slots' LaTeX into **its own LaTeX**, which is the only
///   thing the solve pipeline ever sees.
///
/// A slot index must appear **exactly once** in a template's layout: the
/// renderer maps each [MathSlotPart] to a caret path, and a duplicate would
/// give one slot two carets.
library;

// ---------------------------------------------------------------------------
// Layout description
// ---------------------------------------------------------------------------

/// A piece of a template's visual form. Pure description — no Flutter here.
sealed class MathPart {
  const MathPart();
}

/// The editable child expression at [index] — drawn as a dashed box when empty.
class MathSlotPart extends MathPart {
  const MathSlotPart(this.index);
  final int index;
}

/// Fixed glyphs the template draws itself (`d`, `lim`, `(`, `,`).
class MathGlyphPart extends MathPart {
  const MathGlyphPart(this.text, {this.upright = false});
  final String text;

  /// Upright (roman) rather than italic — operator names like `lim`, `sin`.
  final bool upright;
}

/// Left-to-right run.
class MathRowPart extends MathPart {
  const MathRowPart(this.parts);
  final List<MathPart> parts;
}

/// Numerator over denominator with a rule between.
class MathFracPart extends MathPart {
  const MathFracPart(this.top, this.bottom);
  final MathPart top;
  final MathPart bottom;
}

/// A radical, optionally with a small index in the crook (`∛`).
class MathRadicalPart extends MathPart {
  const MathRadicalPart(this.radicand, {this.index});
  final MathPart radicand;
  final MathPart? index;
}

/// [base] with a raised [sup] and/or lowered [sub] script after it.
class MathScriptPart extends MathPart {
  const MathScriptPart({required this.base, this.sup, this.sub});
  final MathPart base;
  final MathPart? sup;
  final MathPart? sub;
}

/// A lone raised or lowered script with no base of its own (`ₙ` in `ₙCᵣ`).
class MathLoneScriptPart extends MathPart {
  const MathLoneScriptPart(this.child, {required this.raised});
  final MathPart child;
  final bool raised;
}

/// [child] wrapped in brackets that grow with it.
class MathDelimitedPart extends MathPart {
  const MathDelimitedPart(this.child, {this.left = '(', this.right = ')'});
  final MathPart child;
  final String left;
  final String right;
}

/// A big operator (`lim`, `∑`, `∫`) with limits set under and/or over it.
class MathLimitsPart extends MathPart {
  const MathLimitsPart({
    required this.base,
    this.under,
    this.over,
    this.inline = false,
  });
  final MathPart base;
  final MathPart? under;
  final MathPart? over;

  /// Set the limits beside the operator (as `∫` does) rather than above and
  /// below it (as `∑` and `lim` do).
  final bool inline;
}

/// A bar drawn over [child] — complex conjugate.
class MathOverlinePart extends MathPart {
  const MathOverlinePart(this.child);
  final MathPart child;
}

/// A bracketed grid — matrices and determinants.
class MathGridPart extends MathPart {
  const MathGridPart(this.rows, {this.left = '[', this.right = ']'});
  final List<List<MathPart>> rows;
  final String left;
  final String right;
}

// ---------------------------------------------------------------------------
// Template
// ---------------------------------------------------------------------------

/// One structured construct the keyboard can insert.
class MathTemplate {
  const MathTemplate({
    required this.id,
    required this.slotCount,
    required this.layout,
    required this.build,
    this.hasOwnContent = false,
  });

  /// Stable identity — also what the LaTeX parser round-trips through.
  final String id;

  final int slotCount;

  /// How it looks (see [MathPart]).
  final MathPart layout;

  /// Its LaTeX, given each slot's LaTeX in order.
  final String Function(List<String> slots) build;

  /// Whether the template carries math even with every slot empty (`dy/dx`,
  /// `log₁₀`) — so validation doesn't call such an input "no math yet".
  final bool hasOwnContent;

  String toLatex(List<String> slots) => build(slots);
}

/// Wraps a slot's LaTeX in braces when it isn't already a single token, so
/// `{x+1}^{2}` never degrades into `x+1^{2}`.
String _grp(String s) {
  if (s.isEmpty) return '{}';
  if (s.length == 1) return s;
  return '{$s}';
}

/// Braces a slot for a mandatory LaTeX argument (`\frac`, `\sqrt`).
String _arg(String s) => '{$s}';

const _box = MathSlotPart(0);

/// Every template the keyboard can insert, by [MathTemplate.id].
class MathTemplates {
  const MathTemplates._();

  // -- Basics ---------------------------------------------------------------

  static const paren = MathTemplate(
    id: 'paren',
    slotCount: 1,
    layout: MathDelimitedPart(_box),
    build: _parenLatex,
  );

  static const frac = MathTemplate(
    id: 'frac',
    slotCount: 2,
    layout: MathFracPart(MathSlotPart(0), MathSlotPart(1)),
    build: _fracLatex,
  );

  static const sqrt = MathTemplate(
    id: 'sqrt',
    slotCount: 1,
    layout: MathRadicalPart(_box),
    build: _sqrtLatex,
  );

  static const cbrt = MathTemplate(
    id: 'cbrt',
    slotCount: 1,
    layout: MathRadicalPart(_box, index: MathGlyphPart('3')),
    build: _cbrtLatex,
    hasOwnContent: true,
  );

  static const nthroot = MathTemplate(
    id: 'nthroot',
    slotCount: 2,
    layout: MathRadicalPart(MathSlotPart(1), index: MathSlotPart(0)),
    build: _nthrootLatex,
  );

  static const square = MathTemplate(
    id: 'square',
    slotCount: 1,
    layout: MathScriptPart(base: _box, sup: MathGlyphPart('2')),
    build: _squareLatex,
    hasOwnContent: true,
  );

  static const cube = MathTemplate(
    id: 'cube',
    slotCount: 1,
    layout: MathScriptPart(base: _box, sup: MathGlyphPart('3')),
    build: _cubeLatex,
    hasOwnContent: true,
  );

  static const power = MathTemplate(
    id: 'power',
    slotCount: 2,
    layout: MathScriptPart(base: MathSlotPart(0), sup: MathSlotPart(1)),
    build: _powerLatex,
  );

  static const subscript = MathTemplate(
    id: 'subscript',
    slotCount: 2,
    layout: MathScriptPart(base: MathSlotPart(0), sub: MathSlotPart(1)),
    build: _subscriptLatex,
  );

  /// Both scripts on one base — `x_1^2`, `\int_a^b`. LaTeX writes these as two
  /// separate scripts, so the parser folds them into this rather than nesting a
  /// power around a subscript (which would stagger them at two heights).
  static const subsup = MathTemplate(
    id: 'subsup',
    slotCount: 3,
    layout: MathScriptPart(
      base: MathSlotPart(0),
      sub: MathSlotPart(1),
      sup: MathSlotPart(2),
    ),
    build: _subsupLatex,
  );

  static const bracket = MathTemplate(
    id: 'bracket',
    slotCount: 1,
    layout: MathDelimitedPart(_box, left: '[', right: ']'),
    build: _bracketLatex,
  );

  static const braceSet = MathTemplate(
    id: 'braceSet',
    slotCount: 1,
    layout: MathDelimitedPart(_box, left: '{', right: '}'),
    build: _braceSetLatex,
  );

  static const abs = MathTemplate(
    id: 'abs',
    slotCount: 1,
    layout: MathDelimitedPart(_box, left: '|', right: '|'),
    build: _absLatex,
  );

  static const percent = MathTemplate(
    id: 'percent',
    slotCount: 1,
    layout: MathRowPart([_box, MathGlyphPart('%')]),
    build: _percentLatex,
    hasOwnContent: true,
  );

  // -- Functions, logs, complex, combinatorics ------------------------------

  static const apply = MathTemplate(
    id: 'apply',
    slotCount: 2,
    layout: MathRowPart([MathSlotPart(0), MathDelimitedPart(MathSlotPart(1))]),
    build: _applyLatex,
  );

  static const apply2 = MathTemplate(
    id: 'apply2',
    slotCount: 3,
    layout: MathRowPart([
      MathSlotPart(0),
      MathDelimitedPart(MathRowPart([
        MathSlotPart(1),
        MathGlyphPart(','),
        MathSlotPart(2),
      ])),
    ]),
    build: _apply2Latex,
  );

  static const logBase = MathTemplate(
    id: 'logBase',
    slotCount: 2,
    layout: MathRowPart([
      MathScriptPart(base: MathGlyphPart('log', upright: true), sub: MathSlotPart(0)),
      MathDelimitedPart(MathSlotPart(1)),
    ]),
    build: _logBaseLatex,
    hasOwnContent: true,
  );

  static const conjugate = MathTemplate(
    id: 'conjugate',
    slotCount: 1,
    layout: MathOverlinePart(_box),
    build: _conjugateLatex,
  );

  static const list3 = MathTemplate(
    id: 'list3',
    slotCount: 3,
    layout: MathRowPart([
      MathSlotPart(0),
      MathGlyphPart(', '),
      MathSlotPart(1),
      MathGlyphPart(', '),
      MathSlotPart(2),
    ]),
    build: _list3Latex,
  );

  static const listEllipsis = MathTemplate(
    id: 'listEllipsis',
    slotCount: 3,
    layout: MathRowPart([
      MathSlotPart(0),
      MathGlyphPart(', '),
      MathSlotPart(1),
      MathGlyphPart(', '),
      MathSlotPart(2),
      MathGlyphPart(', …'),
    ]),
    build: _listEllipsisLatex,
    hasOwnContent: true,
  );

  static const factorial = MathTemplate(
    id: 'factorial',
    slotCount: 1,
    layout: MathRowPart([_box, MathGlyphPart('!')]),
    build: _factorialLatex,
    hasOwnContent: true,
  );

  static const binomial = MathTemplate(
    id: 'binomial',
    slotCount: 2,
    layout: MathDelimitedPart(
      MathFracPart(MathSlotPart(0), MathSlotPart(1)),
    ),
    build: _binomialLatex,
  );

  static const combinations = MathTemplate(
    id: 'combinations',
    slotCount: 2,
    layout: MathRowPart([
      MathLoneScriptPart(MathSlotPart(0), raised: false),
      MathGlyphPart('C', upright: true),
      MathLoneScriptPart(MathSlotPart(1), raised: false),
    ]),
    build: _combinationsLatex,
    hasOwnContent: true,
  );

  static const permutations = MathTemplate(
    id: 'permutations',
    slotCount: 2,
    layout: MathRowPart([
      MathLoneScriptPart(MathSlotPart(0), raised: false),
      MathGlyphPart('P', upright: true),
      MathLoneScriptPart(MathSlotPart(1), raised: false),
    ]),
    build: _permutationsLatex,
    hasOwnContent: true,
  );

  static const variations = MathTemplate(
    id: 'variations',
    slotCount: 2,
    layout: MathRowPart([
      MathLoneScriptPart(MathSlotPart(0), raised: false),
      MathGlyphPart('V', upright: true),
      MathLoneScriptPart(MathSlotPart(1), raised: false),
    ]),
    build: _variationsLatex,
    hasOwnContent: true,
  );

  static const matrix2x2 = MathTemplate(
    id: 'matrix2x2',
    slotCount: 4,
    layout: MathGridPart([
      [MathSlotPart(0), MathSlotPart(1)],
      [MathSlotPart(2), MathSlotPart(3)],
    ]),
    build: _matrixLatex,
  );

  static const determinant2x2 = MathTemplate(
    id: 'determinant2x2',
    slotCount: 4,
    layout: MathGridPart(
      [
        [MathSlotPart(0), MathSlotPart(1)],
        [MathSlotPart(2), MathSlotPart(3)],
      ],
      left: '|',
      right: '|',
    ),
    build: _determinantLatex,
  );

  static const matrix3x3 = MathTemplate(
    id: 'matrix3x3',
    slotCount: 9,
    layout: MathGridPart([
      [MathSlotPart(0), MathSlotPart(1), MathSlotPart(2)],
      [MathSlotPart(3), MathSlotPart(4), MathSlotPart(5)],
      [MathSlotPart(6), MathSlotPart(7), MathSlotPart(8)],
    ]),
    build: _matrix3Latex,
  );

  static const vector2 = MathTemplate(
    id: 'vector2',
    slotCount: 2,
    layout: MathGridPart([
      [MathSlotPart(0)],
      [MathSlotPart(1)],
    ]),
    build: _vector2Latex,
  );

  // -- Trigonometry ---------------------------------------------------------

  static const degrees = MathTemplate(
    id: 'degrees',
    slotCount: 1,
    layout: MathScriptPart(base: _box, sup: MathGlyphPart('∘')),
    build: _degreesLatex,
    hasOwnContent: true,
  );

  static const degMin = MathTemplate(
    id: 'degMin',
    slotCount: 2,
    layout: MathRowPart([
      MathScriptPart(base: MathSlotPart(0), sup: MathGlyphPart('∘')),
      MathScriptPart(base: MathSlotPart(1), sup: MathGlyphPart('′')),
    ]),
    build: _degMinLatex,
    hasOwnContent: true,
  );

  static const degMinSec = MathTemplate(
    id: 'degMinSec',
    slotCount: 3,
    layout: MathRowPart([
      MathScriptPart(base: MathSlotPart(0), sup: MathGlyphPart('∘')),
      MathScriptPart(base: MathSlotPart(1), sup: MathGlyphPart('′')),
      MathScriptPart(base: MathSlotPart(2), sup: MathGlyphPart('″')),
    ]),
    build: _degMinSecLatex,
    hasOwnContent: true,
  );

  // -- Calculus -------------------------------------------------------------

  static const limit = MathTemplate(
    id: 'limit',
    slotCount: 2,
    layout: MathLimitsPart(
      base: MathGlyphPart('lim', upright: true),
      under: MathRowPart([
        MathSlotPart(0),
        MathGlyphPart('→'),
        MathSlotPart(1),
      ]),
    ),
    build: _limitLatex,
    hasOwnContent: true,
  );

  static const limitRight = MathTemplate(
    id: 'limitRight',
    slotCount: 2,
    layout: MathLimitsPart(
      base: MathGlyphPart('lim', upright: true),
      under: MathRowPart([
        MathSlotPart(0),
        MathGlyphPart('→'),
        MathScriptPart(base: MathSlotPart(1), sup: MathGlyphPart('+')),
      ]),
    ),
    build: _limitRightLatex,
    hasOwnContent: true,
  );

  static const limitLeft = MathTemplate(
    id: 'limitLeft',
    slotCount: 2,
    layout: MathLimitsPart(
      base: MathGlyphPart('lim', upright: true),
      under: MathRowPart([
        MathSlotPart(0),
        MathGlyphPart('→'),
        MathScriptPart(base: MathSlotPart(1), sup: MathGlyphPart('−')),
      ]),
    ),
    build: _limitLeftLatex,
    hasOwnContent: true,
  );

  static const derivativeX = MathTemplate(
    id: 'derivativeX',
    slotCount: 1,
    layout: MathRowPart([
      MathFracPart(
        MathGlyphPart('d'),
        MathRowPart([MathGlyphPart('d'), MathGlyphPart('x')]),
      ),
      _box,
    ]),
    build: _derivativeXLatex,
    hasOwnContent: true,
  );

  static const derivative = MathTemplate(
    id: 'derivative',
    slotCount: 2,
    layout: MathRowPart([
      MathFracPart(
        MathGlyphPart('d'),
        MathRowPart([MathGlyphPart('d'), MathSlotPart(0)]),
      ),
      MathSlotPart(1),
    ]),
    build: _derivativeLatex,
    hasOwnContent: true,
  );

  static const secondDerivative = MathTemplate(
    id: 'secondDerivative',
    slotCount: 2,
    layout: MathRowPart([
      MathFracPart(
        MathScriptPart(base: MathGlyphPart('d'), sup: MathGlyphPart('2')),
        MathRowPart([
          MathGlyphPart('d'),
          MathScriptPart(base: MathSlotPart(0), sup: MathGlyphPart('2')),
        ]),
      ),
      MathSlotPart(1),
    ]),
    build: _secondDerivativeLatex,
    hasOwnContent: true,
  );

  static const integral = MathTemplate(
    id: 'integral',
    slotCount: 1,
    layout: MathRowPart([
      MathGlyphPart('∫'),
      _box,
      MathGlyphPart('dx'),
    ]),
    build: _integralLatex,
    hasOwnContent: true,
  );

  static const integralVar = MathTemplate(
    id: 'integralVar',
    slotCount: 2,
    layout: MathRowPart([
      MathGlyphPart('∫'),
      MathSlotPart(0),
      MathGlyphPart('d'),
      MathSlotPart(1),
    ]),
    build: _integralVarLatex,
    hasOwnContent: true,
  );

  static const integralDefinite = MathTemplate(
    id: 'integralDefinite',
    slotCount: 4,
    layout: MathRowPart([
      MathLimitsPart(
        base: MathGlyphPart('∫'),
        under: MathSlotPart(0),
        over: MathSlotPart(1),
        inline: true,
      ),
      MathSlotPart(2),
      MathGlyphPart('d'),
      MathSlotPart(3),
    ]),
    build: _integralDefiniteLatex,
    hasOwnContent: true,
  );

  static const sum = MathTemplate(
    id: 'sum',
    slotCount: 3,
    layout: MathLimitsPart(
      base: MathGlyphPart('∑'),
      under: MathRowPart([
        MathSlotPart(0),
        MathGlyphPart('='),
        MathSlotPart(1),
      ]),
      over: MathSlotPart(2),
    ),
    build: _sumLatex,
    hasOwnContent: true,
  );

  static const product = MathTemplate(
    id: 'product',
    slotCount: 3,
    layout: MathLimitsPart(
      base: MathGlyphPart('∏'),
      under: MathRowPart([
        MathSlotPart(0),
        MathGlyphPart('='),
        MathSlotPart(1),
      ]),
      over: MathSlotPart(2),
    ),
    build: _productLatex,
    hasOwnContent: true,
  );

  static const dydx = MathTemplate(
    id: 'dydx',
    slotCount: 0,
    layout: MathFracPart(
      MathRowPart([MathGlyphPart('d'), MathGlyphPart('y')]),
      MathRowPart([MathGlyphPart('d'), MathGlyphPart('x')]),
    ),
    build: _dydxLatex,
    hasOwnContent: true,
  );

  static const partial = MathTemplate(
    id: 'partial',
    slotCount: 2,
    layout: MathRowPart([
      MathFracPart(
        MathGlyphPart('∂'),
        MathRowPart([MathGlyphPart('∂'), MathSlotPart(0)]),
      ),
      MathSlotPart(1),
    ]),
    build: _partialLatex,
    hasOwnContent: true,
  );

  /// Named functions — `sin(□)`, `ln(□)`, `sign(□)` … built from a shared
  /// shape so adding one is a single line.
  static final Map<String, MathTemplate> functions = Map.unmodifiable({
    for (final f in _functionNames) f: _function(f),
  });

  static const _functionNames = <String>[
    'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
    'arcsin', 'arccos', 'arctan', 'arccot', 'arcsec', 'arccsc',
    'sinh', 'cosh', 'tanh', 'coth', 'sech', 'csch',
    'arsinh', 'arcosh', 'artanh', 'arcoth', 'arsech', 'arcsch',
    'ln', 'exp', 'sign', 'log',
  ];

  /// LaTeX commands that exist as primitives; everything else needs
  /// `\operatorname{…}` so it still typesets upright.
  static const _builtinCommands = <String>{
    'sin', 'cos', 'tan', 'cot', 'sec', 'csc',
    'arcsin', 'arccos', 'arctan', 'sinh', 'cosh', 'tanh', 'coth',
    'ln', 'exp', 'log',
  };

  static String commandFor(String name) => _builtinCommands.contains(name)
      ? '\\$name'
      : '\\operatorname{$name}';

  static MathTemplate _function(String name) => MathTemplate(
        id: 'fn:$name',
        slotCount: 1,
        layout: MathRowPart([
          MathGlyphPart(name, upright: true),
          const MathDelimitedPart(_box),
        ]),
        build: (s) => '${commandFor(name)}\\left(${s[0]}\\right)',
        hasOwnContent: true,
      );

  /// `log₁₀(□)` / `log₂(□)` — a log with a baked-in base.
  static MathTemplate logWithBase(String base) => MathTemplate(
        id: 'log$base',
        slotCount: 1,
        layout: MathRowPart([
          MathScriptPart(
            base: const MathGlyphPart('log', upright: true),
            sub: MathGlyphPart(base),
          ),
          const MathDelimitedPart(_box),
        ]),
        build: (s) => '\\log_{$base}\\left(${s[0]}\\right)',
        hasOwnContent: true,
      );

  static final log10 = logWithBase('10');
  static final log2 = logWithBase('2');

  /// Every template, keyed by [MathTemplate.id] — the parser's lookup table.
  static final Map<String, MathTemplate> byId = Map.unmodifiable({
    for (final t in all) t.id: t,
  });

  static final List<MathTemplate> all = List.unmodifiable(<MathTemplate>[
    paren, bracket, braceSet, frac, sqrt, cbrt, nthroot, square, cube, power,
    subscript, subsup, abs,
    percent, apply, apply2, logBase, log10, log2, conjugate, list3,
    listEllipsis, factorial, binomial, combinations, permutations, variations,
    matrix2x2, determinant2x2, matrix3x3, vector2, degrees, degMin, degMinSec,
    limit, limitRight, limitLeft, derivativeX, derivative, secondDerivative,
    integral, integralVar, integralDefinite, sum, product, dydx, partial,
    ...functions.values,
  ]);
}

// -- LaTeX builders (top-level so the templates stay `const`) ----------------

String _parenLatex(List<String> s) => '\\left(${s[0]}\\right)';
String _bracketLatex(List<String> s) => '\\left[${s[0]}\\right]';
String _braceSetLatex(List<String> s) => '\\left\\{${s[0]}\\right\\}';
String _fracLatex(List<String> s) => '\\frac${_arg(s[0])}${_arg(s[1])}';
String _sqrtLatex(List<String> s) => '\\sqrt${_arg(s[0])}';
String _cbrtLatex(List<String> s) => '\\sqrt[3]${_arg(s[0])}';
String _nthrootLatex(List<String> s) => '\\sqrt[${s[0]}]${_arg(s[1])}';
String _squareLatex(List<String> s) => '${_grp(s[0])}^{2}';
String _cubeLatex(List<String> s) => '${_grp(s[0])}^{3}';
String _powerLatex(List<String> s) => '${_grp(s[0])}^${_arg(s[1])}';
String _subscriptLatex(List<String> s) => '${_grp(s[0])}_${_arg(s[1])}';
String _subsupLatex(List<String> s) =>
    '${_grp(s[0])}_${_arg(s[1])}^${_arg(s[2])}';
String _absLatex(List<String> s) => '\\left|${s[0]}\\right|';
String _percentLatex(List<String> s) => '${s[0]}\\%';
String _applyLatex(List<String> s) => '${s[0]}\\left(${s[1]}\\right)';
String _apply2Latex(List<String> s) => '${s[0]}\\left(${s[1]},${s[2]}\\right)';
String _logBaseLatex(List<String> s) => '\\log_${_arg(s[0])}\\left(${s[1]}\\right)';
String _conjugateLatex(List<String> s) => '\\overline${_arg(s[0])}';
String _list3Latex(List<String> s) => '${s[0]}, ${s[1]}, ${s[2]}';
String _listEllipsisLatex(List<String> s) =>
    '${s[0]}, ${s[1]}, ${s[2]}, \\dots';
String _factorialLatex(List<String> s) => '${_grp(s[0])}!';
String _binomialLatex(List<String> s) => '\\binom${_arg(s[0])}${_arg(s[1])}';
String _combinationsLatex(List<String> s) => '{}_${_arg(s[0])}C_${_arg(s[1])}';
String _permutationsLatex(List<String> s) => '{}_${_arg(s[0])}P_${_arg(s[1])}';
String _variationsLatex(List<String> s) => '{}_${_arg(s[0])}V_${_arg(s[1])}';
String _matrixLatex(List<String> s) =>
    '\\begin{bmatrix}${s[0]} & ${s[1]} \\\\ ${s[2]} & ${s[3]}\\end{bmatrix}';
String _determinantLatex(List<String> s) =>
    '\\begin{vmatrix}${s[0]} & ${s[1]} \\\\ ${s[2]} & ${s[3]}\\end{vmatrix}';
String _matrix3Latex(List<String> s) => '\\begin{bmatrix}'
    '${s[0]} & ${s[1]} & ${s[2]} \\\\ '
    '${s[3]} & ${s[4]} & ${s[5]} \\\\ '
    '${s[6]} & ${s[7]} & ${s[8]}\\end{bmatrix}';
String _vector2Latex(List<String> s) =>
    '\\begin{bmatrix}${s[0]} \\\\ ${s[1]}\\end{bmatrix}';
String _degreesLatex(List<String> s) => '${_grp(s[0])}^{\\circ}';
String _degMinLatex(List<String> s) =>
    "${_grp(s[0])}^{\\circ}${_grp(s[1])}'";
String _degMinSecLatex(List<String> s) =>
    "${_grp(s[0])}^{\\circ}${_grp(s[1])}'${_grp(s[2])}''";
String _limitLatex(List<String> s) => '\\lim_{${s[0]} \\to ${s[1]}}';
String _limitRightLatex(List<String> s) =>
    '\\lim_{${s[0]} \\to ${s[1]}^{+}}';
String _limitLeftLatex(List<String> s) => '\\lim_{${s[0]} \\to ${s[1]}^{-}}';
String _derivativeXLatex(List<String> s) =>
    '\\frac{d}{dx}\\left(${s[0]}\\right)';
String _derivativeLatex(List<String> s) =>
    '\\frac{d}{d${_grp(s[0])}}\\left(${s[1]}\\right)';
String _secondDerivativeLatex(List<String> s) =>
    '\\frac{d^{2}}{d${_grp(s[0])}^{2}}\\left(${s[1]}\\right)';
String _integralLatex(List<String> s) => '\\int ${s[0]} \\,dx';
String _integralVarLatex(List<String> s) => '\\int ${s[0]} \\,d${_grp(s[1])}';
String _integralDefiniteLatex(List<String> s) =>
    '\\int_${_arg(s[0])}^${_arg(s[1])} ${s[2]} \\,d${_grp(s[3])}';
String _sumLatex(List<String> s) => '\\sum_{${s[0]}=${s[1]}}^${_arg(s[2])}';
String _productLatex(List<String> s) => '\\prod_{${s[0]}=${s[1]}}^${_arg(s[2])}';
String _dydxLatex(List<String> s) => '\\frac{dy}{dx}';
String _partialLatex(List<String> s) =>
    '\\frac{\\partial}{\\partial ${s[0]}}\\left(${s[1]}\\right)';
