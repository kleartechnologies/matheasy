/// What the math keyboard offers, laid out as the grid it is drawn in.
///
/// The catalogue is pure data. A key either inserts a leaf glyph or opens a
/// structured [MathTemplate] with dashed boxes to fill in; keys marked with a
/// dot carry [MathKeySpec.alternates] reachable on long-press, which is how the
/// less-common relations, roots and variables stay one gesture away without
/// doubling the number of visible keys.
library;

import '../../domain/math_node.dart';
import '../../domain/math_templates.dart';

/// One key.
class MathKeySpec {
  const MathKeySpec({
    required this.label,
    this.atom,
    this.template,
    this.face,
    this.facePart,
    this.wrapPrevious = false,
    this.alternates = const [],
  });

  /// Accessibility label — also the tooltip on long-press alternates.
  final String label;

  /// The glyph this key inserts, when it is a leaf key.
  final MathAtom? atom;

  /// The structure this key opens, when it is a template key.
  final MathTemplate? template;

  /// Draws the face as plain text instead of a miniature of [template] — for
  /// keys like `sin` whose full form (`sin(□)`) would be too wide to read.
  final String? face;

  /// Draws the face from a custom layout — for keys that want to show only
  /// part of what they insert (`log_□` rather than `log_□(□)`).
  final MathPart? facePart;

  /// Whether the template should swallow the operand before the caret, so
  /// `12` then `x²` reads `12²` rather than `12□²`.
  final bool wrapPrevious;

  /// Reachable by long-pressing this key.
  final List<MathKeySpec> alternates;

  bool get hasAlternates => alternates.isNotEmpty;
}

/// A page of keys.
class MathKeyTab {
  const MathKeyTab({
    required this.id,
    required this.labelTop,
    required this.labelBottom,
    required this.rows,
  });

  final String id;

  /// The two lines of the tab chip, as on the reference keyboard.
  final String labelTop;
  final String labelBottom;

  /// The grid. `null` is a blank cell — the grid is never ragged.
  final List<List<MathKeySpec?>> rows;

  int get columns =>
      rows.fold(0, (max, r) => r.length > max ? r.length : max);
}

// -- Builders ---------------------------------------------------------------

MathKeySpec _atom(
  String display, {
  String? latex,
  String? label,
  List<MathKeySpec> alternates = const [],
}) =>
    MathKeySpec(
      label: label ?? display,
      atom: MathAtom(latex: latex ?? display, display: display),
      alternates: alternates,
    );

MathKeySpec _op(String display, String latex, {String? label}) => MathKeySpec(
      label: label ?? display,
      atom: MathAtom(
        latex: latex,
        display: display,
        render: MathAtomRender.operatorName,
      ),
    );

MathKeySpec _tpl(
  MathTemplate template, {
  required String label,
  String? face,
  MathPart? facePart,
  bool wrapPrevious = false,
  List<MathKeySpec> alternates = const [],
}) =>
    MathKeySpec(
      label: label,
      template: template,
      face: face,
      facePart: facePart,
      wrapPrevious: wrapPrevious,
      alternates: alternates,
    );

MathKeySpec _fn(String name, {String? face}) => _tpl(
      MathTemplates.functions[name]!,
      label: name,
      face: face ?? name,
    );

/// The keyboard's pages, in order.
class MathKeys {
  const MathKeys._();

  static final List<MathKeyTab> tabs = List.unmodifiable([
    _basics,
    _functions,
    _trigonometry,
    _calculus,
  ]);

  /// The letters page, reached from the `abc` button rather than a tab chip.
  static final MathKeyTab letters = MathKeyTab(
    id: 'abc',
    labelTop: 'abc',
    labelBottom: '',
    rows: [
      [for (final c in 'abcdefgh'.split('')) _atom(c)],
      [for (final c in 'ijklmnop'.split('')) _atom(c)],
      [for (final c in 'qrstuvwx'.split('')) _atom(c)],
      [
        _atom('y'),
        _atom('z'),
        _atom('α', latex: r'\alpha ', label: 'alpha'),
        _atom('β', latex: r'\beta ', label: 'beta'),
        _atom('θ', latex: r'\theta ', label: 'theta'),
        _atom('ρ', latex: r'\rho ', label: 'rho'),
        _atom('φ', latex: r'\phi ', label: 'phi'),
        _atom('Δ', latex: r'\Delta ', label: 'Delta'),
      ],
    ],
  );

  // -- Numbers and operators ------------------------------------------------

  static final MathKeyTab _basics = MathKeyTab(
    id: 'basics',
    labelTop: '+ −',
    labelBottom: '× ÷',
    rows: [
      [
        _tpl(
          MathTemplates.paren,
          label: 'parentheses',
          alternates: [
            _tpl(MathTemplates.bracket, label: 'square brackets'),
            _tpl(MathTemplates.braceSet, label: 'braces'),
            _tpl(MathTemplates.abs, label: 'absolute value'),
          ],
        ),
        _atom(
          '>',
          label: 'greater than',
          alternates: [
            _atom('<', label: 'less than'),
            _atom('≥', latex: r'\ge ', label: 'greater than or equal'),
            _atom('≤', latex: r'\le ', label: 'less than or equal'),
            _atom('≠', latex: r'\ne ', label: 'not equal'),
            _atom('≈', latex: r'\approx ', label: 'approximately'),
          ],
        ),
        _atom('7'), _atom('8'), _atom('9'),
        _atom('÷', latex: r'\div '),
      ],
      [
        _tpl(
          MathTemplates.frac,
          label: 'fraction',
          alternates: [
            _tpl(MathTemplates.binomial, label: 'binomial coefficient'),
          ],
        ),
        _tpl(
          MathTemplates.sqrt,
          label: 'square root',
          alternates: [
            _tpl(MathTemplates.cbrt, label: 'cube root'),
            _tpl(MathTemplates.nthroot, label: 'nth root'),
          ],
        ),
        _atom('4'), _atom('5'), _atom('6'),
        _atom('×', latex: r'\times '),
      ],
      [
        _tpl(
          MathTemplates.square,
          label: 'squared',
          wrapPrevious: true,
          alternates: [
            _tpl(MathTemplates.cube, label: 'cubed', wrapPrevious: true),
            _tpl(MathTemplates.power, label: 'power', wrapPrevious: true),
            _tpl(MathTemplates.subscript, label: 'subscript',
                wrapPrevious: true),
          ],
        ),
        _atom(
          'x',
          alternates: [
            _atom('y'), _atom('z'), _atom('a'), _atom('b'), _atom('n'),
            _atom('θ', latex: r'\theta ', label: 'theta'),
          ],
        ),
        _atom('1'), _atom('2'), _atom('3'),
        _atom('−', latex: '-', label: 'minus'),
      ],
      [
        _atom(
          'π',
          latex: r'\pi ',
          label: 'pi',
          alternates: [
            _atom('e'),
            _atom('∞', latex: r'\infty ', label: 'infinity'),
            _atom('i', label: 'imaginary unit'),
          ],
        ),
        _tpl(
          MathTemplates.percent,
          label: 'percent',
          wrapPrevious: true,
          alternates: [
            _tpl(MathTemplates.degrees, label: 'degrees', wrapPrevious: true),
          ],
        ),
        _atom('0'), _atom('.', label: 'decimal point'),
        _atom('=', label: 'equals'),
        _atom('+', label: 'plus'),
      ],
    ],
  );

  // -- Functions, logs, complex numbers, combinatorics ----------------------

  static final MathKeyTab _functions = MathKeyTab(
    id: 'functions',
    labelTop: 'f(x)  e',
    labelBottom: 'log  ln',
    rows: [
      [
        _tpl(MathTemplates.abs, label: 'absolute value'),
        _atom('f(x)', latex: 'f(x)', label: 'f of x'),
        _tpl(MathTemplates.log10, label: 'log base 10', face: 'log₁₀'),
        _tpl(MathTemplates.variations, label: 'variations'),
        _atom('i', label: 'imaginary unit'),
        _tpl(MathTemplates.list3, label: 'list'),
      ],
      [
        _tpl(
          MathTemplates.subscript,
          label: 'subscript',
          alternates: [_tpl(MathTemplates.power, label: 'power')],
        ),
        _tpl(MathTemplates.apply, label: 'function of'),
        _tpl(MathTemplates.log2, label: 'log base 2', face: 'log₂'),
        _tpl(MathTemplates.permutations, label: 'permutations'),
        _atom('z', label: 'complex z'),
        _tpl(MathTemplates.factorial, label: 'factorial', wrapPrevious: true),
      ],
      [
        _atom('e', label: "Euler's number"),
        _atom('f(x,y)', latex: 'f(x,y)', label: 'f of x and y'),
        _tpl(
          MathTemplates.logBase,
          label: 'log with base',
          facePart: const MathScriptPart(
            base: MathGlyphPart('log', upright: true),
            sub: MathSlotPart(0),
          ),
        ),
        _tpl(MathTemplates.combinations, label: 'combinations'),
        _tpl(MathTemplates.conjugate, label: 'complex conjugate'),
        _tpl(
          MathTemplates.matrix2x2,
          label: 'matrix',
          alternates: [
            _tpl(MathTemplates.matrix3x3, label: '3 by 3 matrix'),
            _tpl(MathTemplates.vector2, label: 'column vector'),
          ],
        ),
      ],
      [
        _fn('exp'),
        _tpl(MathTemplates.apply2, label: 'function of two variables'),
        _fn('ln'),
        _tpl(MathTemplates.binomial, label: 'binomial coefficient'),
        _fn('sign'),
        _tpl(MathTemplates.determinant2x2, label: 'determinant'),
      ],
    ],
  );

  // -- Trigonometry ---------------------------------------------------------

  static final MathKeyTab _trigonometry = MathKeyTab(
    id: 'trigonometry',
    labelTop: 'sin  cos',
    labelBottom: 'tan  cot',
    rows: [
      [
        _op('rad', r'\mathrm{rad}', label: 'radians'),
        _fn('sin'), _fn('cos'), _fn('tan'), _fn('cot'), _fn('sec'), _fn('csc'),
      ],
      [
        _tpl(MathTemplates.degrees, label: 'degrees', wrapPrevious: true),
        _fn('arcsin'), _fn('arccos'), _fn('arctan'),
        _fn('arccot'), _fn('arcsec'), _fn('arccsc'),
      ],
      [
        _tpl(MathTemplates.degMin, label: 'degrees and minutes'),
        _fn('sinh'), _fn('cosh'), _fn('tanh'),
        _fn('coth'), _fn('sech'), _fn('csch'),
      ],
      [
        _tpl(MathTemplates.degMinSec, label: 'degrees, minutes and seconds'),
        _fn('arsinh'), _fn('arcosh'), _fn('artanh'),
        _fn('arcoth'), _fn('arsech'), _fn('arcsch'),
      ],
    ],
  );

  // -- Calculus -------------------------------------------------------------

  static final MathKeyTab _calculus = MathKeyTab(
    id: 'calculus',
    labelTop: 'lim  dx',
    labelBottom: '∫ Σ ∞',
    rows: [
      [
        _tpl(MathTemplates.limit, label: 'limit'),
        _tpl(MathTemplates.derivativeX, label: 'derivative with respect to x'),
        _tpl(MathTemplates.integral, label: 'integral'),
        _tpl(MathTemplates.dydx, label: 'dy by dx'),
        _tpl(
          MathTemplates.subscript,
          label: 'sequence term',
          facePart: const MathScriptPart(
            base: MathGlyphPart('a'),
            sub: MathGlyphPart('n'),
          ),
        ),
      ],
      [
        _tpl(MathTemplates.limitRight, label: 'limit from the right'),
        _tpl(
          MathTemplates.derivative,
          label: 'derivative',
          alternates: [
            _tpl(MathTemplates.partial, label: 'partial derivative'),
          ],
        ),
        _tpl(MathTemplates.integralVar, label: 'integral with respect to'),
        _atom('dx', latex: 'dx'),
        _tpl(MathTemplates.listEllipsis, label: 'sequence'),
      ],
      [
        _tpl(MathTemplates.limitLeft, label: 'limit from the left'),
        _tpl(MathTemplates.secondDerivative, label: 'second derivative'),
        _tpl(MathTemplates.integralDefinite, label: 'definite integral'),
        _atom('dy', latex: 'dy'),
        null,
      ],
      [
        _atom('∞', latex: r'\infty ', label: 'infinity'),
        null,
        _tpl(
          MathTemplates.sum,
          label: 'sum',
          alternates: [_tpl(MathTemplates.product, label: 'product')],
        ),
        _atom("y'", latex: "y'", label: 'y prime'),
        null,
      ],
    ],
  );
}
