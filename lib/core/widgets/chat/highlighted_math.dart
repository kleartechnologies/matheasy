import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/theme.dart';

/// Renders an equation with only the part currently under discussion coloured
/// (spec Part 8): never plain text, never the whole line lit up at once, and the
/// colour arrives as a smooth cross-fade rather than a jump.
///
/// The equation is always rendered — highlighting is an enhancement layered on
/// top. If a span can't be applied without corrupting the LaTeX, that span is
/// dropped and the maths still renders, because a readable uncoloured equation
/// beats a coloured broken one.
class HighlightedMath extends StatefulWidget {
  const HighlightedMath({
    super.key,
    required this.latex,
    required this.highlights,
    required this.textStyle,
  });

  final String latex;
  final List<MathHighlight> highlights;
  final TextStyle textStyle;

  @override
  State<HighlightedMath> createState() => _HighlightedMathState();
}

class _HighlightedMathState extends State<HighlightedMath> {
  bool _lit = false;

  @override
  void initState() {
    super.initState();
    // The next frame, so the fade has a 0 → 1 edge to animate across.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _lit = true);
    });
  }

  @override
  void didUpdateWidget(HighlightedMath old) {
    super.didUpdateWidget(old);
    // A different equation or a moved highlight re-plays the reveal, which is
    // what makes a walkthrough read as "now look *here*".
    if (old.latex != widget.latex || !_sameSpans(old.highlights)) {
      _lit = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _lit = true);
      });
    }
  }

  bool _sameSpans(List<MathHighlight> other) {
    if (other.length != widget.highlights.length) return false;
    for (var i = 0; i < other.length; i++) {
      if (other[i] != widget.highlights[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final coloured = colorizeLatex(
      widget.latex,
      widget.highlights,
      (role) => mathRoleHex(role.color(colors, isDark: isDark)),
    );

    final plain = _tex(context, widget.latex);
    if (coloured == widget.latex) return plain;

    return Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [
        // The base layer also sizes the stack, and is what remains visible if
        // the coloured build fails to parse.
        plain,
        AnimatedOpacity(
          opacity: reduceMotion || _lit ? 1 : 0,
          duration: reduceMotion ? Duration.zero : AppDurations.slow,
          curve: Curves.easeOut,
          child: _tex(context, coloured, onError: (_) => const SizedBox.shrink()),
        ),
      ],
    );
  }

  Widget _tex(
    BuildContext context,
    String latex, {
    Widget Function(FlutterMathException)? onError,
  }) {
    return Math.tex(
      latex,
      textStyle: widget.textStyle,
      mathStyle: MathStyle.text,
      onErrorFallback: onError ??
          (_) => Text(widget.latex, style: widget.textStyle),
    );
  }
}

/// Wraps each highlight in `\textcolor{#RRGGBB}{…}`, skipping any span that
/// can't be wrapped without breaking the LaTeX.
///
/// Pure and side-effect free so the rules below are directly testable. The rules
/// exist because a highlight is a *view* over maths the app already verified —
/// it may never change what the equation says:
///
///  * a span must appear verbatim in the LaTeX, and each highlight claims its
///    own occurrence (so highlighting `x` twice tints two different `x`s);
///  * spans may not overlap;
///  * a span may not straddle a `\command` name, unbalance braces, or end on a
///    dangling `^`, `_` or `\`.
String colorizeLatex(
  String latex,
  List<MathHighlight> highlights,
  String Function(MathRole role) hexOf,
) {
  if (latex.isEmpty || highlights.isEmpty) return latex;

  final claimed = <_Span>[];
  for (final h in highlights) {
    final at = _findSafeOccurrence(latex, h.text, claimed);
    if (at < 0) continue;
    claimed.add(_Span(at, at + h.text.length, h.role));
  }
  if (claimed.isEmpty) return latex;

  claimed.sort((a, b) => a.start.compareTo(b.start));
  final out = StringBuffer();
  var cursor = 0;
  for (final span in claimed) {
    out.write(latex.substring(cursor, span.start));
    out.write('\\textcolor{${hexOf(span.role)}}{');
    out.write(latex.substring(span.start, span.end));
    out.write('}');
    cursor = span.end;
  }
  out.write(latex.substring(cursor));
  return out.toString();
}

/// The first occurrence of [needle] that is safe to wrap and free of [claimed],
/// or -1 if there is none.
int _findSafeOccurrence(String latex, String needle, List<_Span> claimed) {
  if (needle.isEmpty) return -1;
  var from = 0;
  while (true) {
    final at = latex.indexOf(needle, from);
    if (at < 0) return -1;
    final end = at + needle.length;
    final free = !claimed.any((c) => at < c.end && c.start < end);
    if (free && _isWrappable(latex, at, end)) return at;
    from = at + 1;
  }
}

/// Whether `latex[start..end)` can be wrapped in a group without changing what
/// the equation means.
bool _isWrappable(String latex, int start, int end) {
  final span = latex.substring(start, end);
  if (span.trim().isEmpty) return false;

  // Alignment markup only means something at the top level of an environment;
  // inside a group it is a parse error.
  if (span.contains('&') || span.contains(r'\\')) return false;

  // A trailing operator would be left with nothing to operate on.
  if (RegExp(r'[\^_\\]$').hasMatch(span)) return false;

  // A leading script would be left with no base.
  if (span.startsWith('^') || span.startsWith('_')) return false;

  // Braces must balance, and must never close a group opened outside the span.
  var depth = 0;
  for (var i = 0; i < span.length; i++) {
    if (i > 0 && span[i - 1] == '\\') continue; // an escaped brace is a glyph
    if (span[i] == '{') depth++;
    if (span[i] == '}') {
      depth--;
      if (depth < 0) return false;
    }
  }
  if (depth != 0) return false;

  // Neither edge may fall inside a `\command` name.
  for (final m in RegExp(r'\\[a-zA-Z]+').allMatches(latex)) {
    if (m.start < start && start < m.end) return false;
    if (m.start < end && end < m.end) return false;
  }
  return true;
}

@immutable
class _Span {
  const _Span(this.start, this.end, this.role);
  final int start;
  final int end;
  final MathRole role;
}
