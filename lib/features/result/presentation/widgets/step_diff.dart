/// LaTeX step-diff for the §5 "highlight what changed" emphasis.
///
/// Between two consecutive step expressions we find the changed contiguous span
/// and wrap it in `\textcolor{…}{…}` so the transformed part renders in the
/// accent colour — the "understand, don't just copy" moment. The math is
/// tokenised into TOP-LEVEL atoms where each atom is self-contained (a `\command`
/// with its `{…}` arguments, a `{…}` group, or a base with its `^…`/`_…`
/// scripts), so a run of atoms is always safe to wrap without splitting a
/// fraction or leaving a dangling superscript.
///
/// Faithfulness caveat: because atoms are top-level, a change DEEP inside a
/// fraction argument highlights the whole fraction atom rather than the inner
/// term. When the whole expression changed (no shared prefix/suffix), there's
/// nothing meaningful to isolate → [emphasizeChanged] returns null and the
/// caller falls back to emphasising the whole line.
library;

bool _isLetter(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122);
}

/// Split [latex] into top-level, self-contained atoms.
List<String> atomize(String latex) {
  final s = latex;
  final atoms = <String>[];
  var i = 0;

  int consumeGroup(int start) {
    // start points at '{' or '['; return the index just past its match.
    final open = s[start];
    final close = open == '{' ? '}' : ']';
    var depth = 0;
    for (var k = start; k < s.length; k++) {
      if (s[k] == open) {
        depth++;
      } else if (s[k] == close) {
        depth--;
        if (depth == 0) return k + 1;
      }
    }
    return s.length; // unbalanced — take the rest
  }

  int consumeScriptArg(int start) {
    // start points just after '^' or '_'; return index past the script argument.
    var j = start;
    while (j < s.length && s[j] == ' ') {
      j++;
    }
    if (j >= s.length) return j;
    if (s[j] == '{') return consumeGroup(j);
    if (s[j] == '\\') {
      var k = j + 1;
      while (k < s.length && _isLetter(s[k])) {
        k++;
      }
      return k == j + 1 ? j + 2 : k; // \pi vs \{
    }
    return j + 1; // a single character
  }

  while (i < s.length) {
    final c = s[i];
    var j = i;

    if (c == ' ') {
      atoms.add(' ');
      i++;
      continue;
    } else if (c == '\\') {
      j = i + 1;
      if (j < s.length && _isLetter(s[j])) {
        while (j < s.length && _isLetter(s[j])) {
          j++;
        }
      } else {
        j = i + 2; // \{  \}  \,  etc.
      }
      // absorb the command's brace/bracket arguments
      while (j < s.length && (s[j] == '{' || s[j] == '[')) {
        j = consumeGroup(j);
      }
    } else if (c == '{') {
      j = consumeGroup(i);
    } else {
      j = i + 1; // a single character base
    }

    // Attach any trailing scripts (^…, _…) to the base atom so it stays valid.
    while (j < s.length && (s[j] == '^' || s[j] == '_')) {
      j = consumeScriptArg(j + 1);
    }

    atoms.add(s.substring(i, j));
    i = j;
  }
  return atoms;
}

/// The changed contiguous span of [curr] relative to [prev], as
/// `(prefix, changed, suffix)` atom lists. `changed` is empty when [curr] is a
/// pure deletion of [prev] (nothing new to emphasise).
({List<String> prefix, List<String> changed, List<String> suffix}) diffAtoms(
  List<String> prev,
  List<String> curr,
) {
  var pre = 0;
  final maxPre = prev.length < curr.length ? prev.length : curr.length;
  while (pre < maxPre && prev[pre] == curr[pre]) {
    pre++;
  }
  var suf = 0;
  while (suf < (maxPre - pre) &&
      prev[prev.length - 1 - suf] == curr[curr.length - 1 - suf]) {
    suf++;
  }
  return (
    prefix: curr.sublist(0, pre),
    changed: curr.sublist(pre, curr.length - suf),
    suffix: curr.sublist(curr.length - suf),
  );
}

/// [curr] with its changed-vs-[prev] span wrapped in `\textcolor{[colorHex]}{…}`.
///
/// Returns null when there's no meaningful isolated change — identical, a pure
/// deletion, or the WHOLE thing changed (no shared prefix/suffix) — so the
/// caller falls back to whole-line emphasis. [colorHex] is `#RRGGBB`.
String? emphasizeChanged(String prev, String curr, {required String colorHex}) {
  if (prev.isEmpty || prev == curr) return null;
  final prevAtoms = atomize(prev);
  final currAtoms = atomize(curr);
  final d = diffAtoms(prevAtoms, currAtoms);
  if (d.changed.isEmpty) return null; // nothing new to highlight
  // If nothing is shared, the "changed" span is the entire expression — not a
  // useful isolate; let the caller emphasise the whole line instead.
  if (d.prefix.isEmpty && d.suffix.isEmpty) return null;

  final changed = d.changed.join();
  return '${d.prefix.join()}\\textcolor{$colorHex}{$changed}${d.suffix.join()}';
}
