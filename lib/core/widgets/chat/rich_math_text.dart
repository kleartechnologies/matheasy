import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Renders a chat message that mixes prose and LaTeX math.
///
/// Math wrapped in `$…$`, `\(…\)`, `$$…$$` or `\[…\]` renders as real equations
/// inline (via flutter_math, with a plain-text fallback if the LaTeX is
/// malformed). Light markdown (`**bold**`) is honoured; code fences, stray
/// backticks, heading `#` and bullet markup are stripped so a tutor reply never
/// shows raw LaTeX, code, or "weird" markup in a bubble — just proper equations
/// and clean prose.
class RichMathText extends StatelessWidget {
  const RichMathText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  // $$block$$ | \[block\] | $inline$ | \(inline\)  (block forms first so `$$`
  // is never mistaken for an empty `$…$`).
  static final RegExp _math = RegExp(
    r'\$\$(.+?)\$\$|\\\[(.+?)\\\]|\$(.+?)\$|\\\((.+?)\\\)',
    dotAll: true,
  );
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');

  @override
  Widget build(BuildContext context) {
    final cleaned = _clean(text);
    final maxMath = MediaQuery.sizeOf(context).width * 0.7;

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _math.allMatches(cleaned)) {
      if (m.start > last) {
        spans.addAll(_prose(cleaned.substring(last, m.start)));
      }
      final latex =
          (m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
      if (latex.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxMath),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Math.tex(
                latex,
                textStyle: style,
                mathStyle: MathStyle.text,
                onErrorFallback: (_) => Text(latex, style: style),
              ),
            ),
          ),
        ));
      }
      last = m.end;
    }
    if (last < cleaned.length) spans.addAll(_prose(cleaned.substring(last)));
    if (spans.isEmpty) spans.add(TextSpan(text: cleaned));

    return Text.rich(TextSpan(style: style, children: spans));
  }

  /// Prose run → text spans, honouring `**bold**` / `__bold__`.
  List<InlineSpan> _prose(String run) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _bold.allMatches(run)) {
      if (m.start > last) out.add(TextSpan(text: run.substring(last, m.start)));
      out.add(TextSpan(
        text: m.group(1) ?? m.group(2),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < run.length) out.add(TextSpan(text: run.substring(last)));
    return out;
  }

  /// Strip markup that has no place in a tutor bubble: fenced code blocks,
  /// stray backticks, heading hashes and list bullets.
  static String _clean(String s) {
    var t = s.replaceAll(RegExp(r'```[\s\S]*?```'), ''); // fenced code blocks
    t = t.replaceAll('`', ''); // stray inline backticks
    t = t.replaceAll(
        RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), ''); // # headings
    t = t.replaceAll(
        RegExp(r'^\s*[-*]\s+', multiLine: true), '• '); // - / * bullets
    return t.trim();
  }
}
