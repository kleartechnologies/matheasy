import 'package:flutter/foundation.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the addressable atom of an equation.
///
/// The morph engine treats an equation as an ordered list of [EqToken]s: signed
/// TERMS (maximal +/- summands) and the RELATION symbol between the two sides.
/// Tokens are the *only* thing the token-diff aligns and the morph view moves —
/// and every token's LaTeX is a substring of the verified before/after LaTeX, so
/// the engine can never introduce a value the solver didn't compute (golden rule).

/// The (in)equation relation that separates the two sides.
enum EqRelation {
  equals('='),
  lt('<'),
  gt('>'),
  le('\\le'),
  ge('\\ge'),
  none('');

  const EqRelation(this.latex);

  /// The delimiter-free LaTeX rendered for this relation.
  final String latex;
}

/// What an [EqToken] represents.
enum EqTokenKind {
  /// A signed summand, e.g. `3x`, `+5`, `-\\frac{1}{2}`.
  term,

  /// The relation symbol (`=`, `<`, …) between the two sides.
  relation,
}

/// One addressable fragment of an equation.
@immutable
class EqToken {
  const EqToken({
    required this.id,
    required this.latex,
    required this.kind,
    required this.side,
    required this.sign,
    required this.key,
  });

  /// Stable identity within a single tokenization (before OR after). The diff
  /// pairs before-ids to after-ids; the morph view slides matched ids.
  final int id;

  /// The fragment as rendered, INCLUDING its leading operator when appropriate
  /// (e.g. `+ 5`, `- 3x`), so a row of tokens reads as the real equation.
  final String latex;

  final EqTokenKind kind;

  /// `0` = left of the relation, `1` = right, `-1` = there is no relation.
  final int side;

  /// `+1` / `-1` for a term (the relation is always `+1`).
  final int sign;

  /// Sign-independent match key, e.g. `5`, `3x`, `x^2`. Two terms with the same
  /// key are "the same term" for the diff even if their sign or side changed.
  final String key;

  bool get isRelation => kind == EqTokenKind.relation;
  bool get isTerm => kind == EqTokenKind.term;

  @override
  String toString() =>
      'EqToken($id ${kind.name} side=$side sign=$sign "$latex" key=$key)';
}
