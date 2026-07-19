import '../../domain/animation/eq_token.dart';
import '../../domain/animation/morph_op.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — aligns two tokenized equation states
/// into a [StepMorph]: which terms stayed, which slid across the relation (with
/// a sign flip), which merged into a new value, which entered or left.
///
/// The alignment is by term KEY (sign-independent), so `+5` on the left pairs
/// with `-5` on the right as a *move*, and `20`,`-5` collapsing to `15` reads as
/// a *merge*. Crucially the engine never computes a value — a merged/entered
/// token's LaTeX is whatever the verified `afterLatex` says it is; the diff only
/// decides how existing tokens travel. It never throws; low-confidence
/// alignments set [StepMorph.confident] to `false` so the view crossfades.
class EquationDiff {
  const EquationDiff._();

  static StepMorph diff(List<EqToken> before, List<EqToken> after) {
    final beforeTerms = before.where((t) => t.isTerm).toList();
    final afterTerms = after.where((t) => t.isTerm).toList();
    if (afterTerms.isEmpty) {
      return StepMorph(
        before: before,
        after: after,
        ops: const [],
        confident: false,
        crossedRelation: false,
        merged: false,
        split: false,
      );
    }

    final ops = <MorphOp>[];
    final usedBefore = <int>{};
    final unmatchedAfter = <EqToken>[];
    var matched = 0;
    var crossed = false;

    // Pass 1 — match each after-term to a same-key before-term (prefer same side).
    for (final a in afterTerms) {
      final b = _findMatch(beforeTerms, a, usedBefore);
      if (b == null) {
        unmatchedAfter.add(a);
        continue;
      }
      usedBefore.add(b.id);
      matched++;
      if (b.side == a.side && b.sign == a.sign) {
        ops.add(MorphOp(kind: MorphKind.keep, fromIds: [b.id], toIds: [a.id]));
      } else {
        ops.add(MorphOp(kind: MorphKind.move, fromIds: [b.id], toIds: [a.id]));
        if (b.side != a.side) crossed = true;
      }
    }

    final unusedBefore =
        beforeTerms.where((t) => !usedBefore.contains(t.id)).toList();

    var merged = false;
    var split = false;

    if (unmatchedAfter.length == 1 && unusedBefore.isNotEmpty) {
      // Several old terms collapse into one new value (e.g. `20 - 5 → 15`).
      ops.add(MorphOp(
        kind: MorphKind.merge,
        fromIds: [for (final b in unusedBefore) b.id],
        toIds: [unmatchedAfter.first.id],
      ));
      merged = unusedBefore.length >= 2 || crossed;
    } else if (unusedBefore.length == 1 && unmatchedAfter.length >= 2) {
      // One old term becomes several (expansion / factoring surfaced as parts).
      ops.add(MorphOp(
        kind: MorphKind.merge, // reuse the many↔one visual (reversed by view)
        fromIds: [unusedBefore.first.id],
        toIds: [for (final a in unmatchedAfter) a.id],
      ));
      split = true;
    } else {
      // No clean collapse — each unmatched after-term simply enters, each
      // unused before-term simply exits (the view fades them).
      for (final a in unmatchedAfter) {
        ops.add(MorphOp(kind: MorphKind.enter, toIds: [a.id]));
      }
      for (final b in unusedBefore) {
        ops.add(MorphOp(kind: MorphKind.exit, fromIds: [b.id]));
      }
    }

    final confident = _confidence(
      matched: matched,
      afterTermCount: afterTerms.length,
      beforeTermCount: beforeTerms.length,
    );

    return StepMorph(
      before: before,
      after: after,
      ops: ops,
      confident: confident,
      crossedRelation: crossed,
      merged: merged,
      split: split,
    );
  }

  static EqToken? _findMatch(
    List<EqToken> beforeTerms,
    EqToken a,
    Set<int> used,
  ) {
    EqToken? sameSide;
    EqToken? anySide;
    for (final b in beforeTerms) {
      if (used.contains(b.id)) continue;
      if (b.key != a.key) continue;
      anySide ??= b;
      if (b.side == a.side) {
        sameSide = b;
        break;
      }
    }
    return sameSide ?? anySide;
  }

  static bool _confidence({
    required int matched,
    required int afterTermCount,
    required int beforeTermCount,
  }) {
    if (afterTermCount == 0) return false;
    if (afterTermCount > 12 || beforeTermCount > 12) return false;
    // At least half of the new state must be traceable to the old state, else
    // the "what changed" story is guesswork — crossfade instead.
    return matched / afterTermCount >= 0.5;
  }
}
