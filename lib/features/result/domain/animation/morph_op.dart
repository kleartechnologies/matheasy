import 'package:flutter/foundation.dart';

import 'eq_token.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the result of diffing two equation
/// states. A [StepMorph] describes, token by token, WHAT CHANGED between the
/// verified `before` and `after` LaTeX — which is exactly what the brief asks
/// every animation to answer.

/// How an after-token relates to the before-state (or how a before-token leaves).
enum MorphKind {
  /// Same token, same side — stays put (may still shift as neighbours move).
  keep,

  /// Same token, but its SIDE and/or SIGN changed — it slides across the `=`.
  move,

  /// A brand-new token with no before-source (e.g. an entered constant).
  enter,

  /// A before-token with no after-match — it fades away.
  exit,

  /// Several before-tokens collapse into one after-token (e.g. `20 - 5 → 15`).
  /// The after-token's value is read from the verified `afterLatex`, never
  /// computed on device.
  merge,
}

/// One token-level change between two equation states.
@immutable
class MorphOp {
  const MorphOp({
    required this.kind,
    this.fromIds = const [],
    this.toIds = const [],
  });

  final MorphKind kind;

  /// before-token ids involved.
  final List<int> fromIds;

  /// after-token ids involved.
  final List<int> toIds;
}

/// The full token-diff for one step: the two tokenized states plus the ops that
/// carry one into the other, and confidence/summary flags the script builder
/// and renderer read.
@immutable
class StepMorph {
  const StepMorph({
    required this.before,
    required this.after,
    required this.ops,
    required this.confident,
    required this.crossedRelation,
    required this.merged,
    required this.split,
  });

  /// An empty diff — nothing to morph (used for the first "understand" beat).
  static const StepMorph empty = StepMorph(
    before: [],
    after: [],
    ops: [],
    confident: false,
    crossedRelation: false,
    merged: false,
    split: false,
  );

  final List<EqToken> before;
  final List<EqToken> after;
  final List<MorphOp> ops;

  /// Whether the alignment is trustworthy enough to animate token-by-token. When
  /// `false`, the renderer degrades to a whole-expression crossfade (never a
  /// misleading move).
  final bool confident;

  /// A term switched sides across the relation (→ MoveTermAcrossEquals).
  final bool crossedRelation;

  /// ≥2 before-tokens collapsed into one after-token (→ MergeTerms).
  final bool merged;

  /// One before-token became several after-tokens (→ SplitExpression/factor).
  final bool split;

  bool get isEmpty => after.isEmpty && before.isEmpty;

  /// The op that produced [afterId], or `null` if it is unchanged/kept.
  MorphOp? opForAfter(int afterId) {
    for (final op in ops) {
      if (op.toIds.contains(afterId)) return op;
    }
    return null;
  }

  /// The before-token ids that leave the stage (fade out).
  Set<int> get exitingBeforeIds {
    final kept = <int>{for (final op in ops) ...op.fromIds};
    return {
      for (final t in before)
        if (t.isTerm && !kept.contains(t.id)) t.id,
    };
  }
}
