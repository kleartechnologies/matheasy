import 'package:flutter/foundation.dart';

import '../../result/domain/result_models.dart';
import '../../scan/domain/detected_equation.dart';

/// One solved problem, cached so it re-opens instantly, offline and free.
///
/// Persists only the LaTeX + the full solution JSON — **never the scan image**
/// (the [DetectedEquation] it carries holds no bytes). This is deliberate: the
/// audience includes minors (8–18), and retaining photographs of their work
/// would be a COPPA/privacy liability with no product benefit.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.canonicalKey,
    required this.result,
    required this.timestampMillis,
  });

  /// The collision-safe cache key derived from the problem LaTeX
  /// ([historyCacheKey]). Two renderings of the same problem (`5x^2` /
  /// `5x^{2}`) share a key; two different problems never do.
  final String canonicalKey;

  /// The complete solved-problem payload — re-rendered on re-open with no
  /// `solve()` call and no scan charge.
  final ResultData result;

  /// When this problem was solved (epoch millis).
  final int timestampMillis;

  DetectedEquation get equation => result.equation;

  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampMillis);

  Map<String, dynamic> toJson() => {
        'canonicalKey': canonicalKey,
        'timestampMillis': timestampMillis,
        'result': result.toJson(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        canonicalKey: j['canonicalKey'] as String? ?? '',
        timestampMillis: (j['timestampMillis'] as num?)?.toInt() ?? 0,
        result: ResultData.fromJson(j['result'] as Map<String, dynamic>),
      );
}

/// Canonicalizes a problem's LaTeX into a stable cache key.
///
/// Correctness rule: the transform must be **collision-safe both ways** —
/// * two renderings of the *same* problem map to the *same* key
///   (`5x^2` ≡ `5x^{2}`), and
/// * two *genuinely different* problems never collide.
///
/// It only applies transforms that preserve mathematical identity, so it is
/// strictly *finer* than the server's `latexToAscii` (it can never merge two
/// problems the solver would distinguish):
/// * drops `\left` / `\right` — pure rendering hints, `\left(` ≡ `(`;
/// * folds `\cdot` and `\times` to `*` — both denote multiplication;
/// * unwraps single-character super/subscript braces — `^{2}` ≡ `^2`, the case
///   that makes `5x^2` and `5x^{2}` agree (multi-char groups like `^{10}` are
///   left intact: bare `^10` means `^1 0`, a different expression);
/// * removes whitespace — LaTeX-insignificant between these tokens (`2 x` ≡
///   `2x`), and applied uniformly so it can only ever merge equivalent inputs.
String historyCacheKey(String latex) {
  var s = latex;
  s = s.replaceAll(r'\left', '').replaceAll(r'\right', '');
  s = s.replaceAll(r'\cdot', '*').replaceAll(r'\times', '*');
  s = s.replaceAllMapped(
    RegExp(r'([_^])\{(\w)\}'),
    (m) => '${m[1]}${m[2]}',
  );
  s = s.replaceAll(RegExp(r'\s+'), '');
  return s;
}
