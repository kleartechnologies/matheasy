import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// Renders a chat message that mixes prose and LaTeX math.
///
/// The goal (the user's explicit requirement): a tutor bubble shows PROPER
/// EQUATIONS and clean prose — never raw LaTeX, code, or "weird" markup, and
/// never crashes. To that end:
///
///  * Math in `$…$`, `\(…\)`, `$$…$$`, `\[…\]` renders via flutter_math. Bare
///    LaTeX commands (`\frac…`) that slipped through un-delimited are rendered
///    too. Unsupported alignment environments (`align`, `gather`, …) are mapped
///    to the supported `aligned`, and a failed parse degrades to sanitised plain
///    text (never raw `\begin`/`&`/`\\`).
///  * A `$` immediately followed by a digit is treated as money, not a math
///    delimiter; stray unmatched `$` are dropped from prose.
///  * Code fences are UNWRAPPED (their contents kept — often the actual working),
///    backticks removed, real headings/bullets tidied, `**bold**` honoured.
///  * Wide equations scroll horizontally instead of shrinking to an unreadable
///    sliver.
class RichMathText extends StatelessWidget {
  const RichMathText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  // $$block$$ | \[block\] | $inline$ (not money) | \(inline\).
  static final RegExp _math = RegExp(
    r'\$\$(.+?)\$\$|\\\[(.+?)\\\]|\$(.+?)\$(?!\d)|\\\((.+?)\\\)',
    dotAll: true,
  );
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');
  // A bare LaTeX command with its brace/script arguments (e.g. \frac{d}{dx}).
  static final RegExp _bareLatex = RegExp(
    r'\\[a-zA-Z]+(?:\{[^{}]*\}|\^\{[^}]*\}|_\{[^}]*\}|\^[0-9A-Za-z]|_[0-9A-Za-z])*',
  );
  // Unsupported alignment environments → the one flutter_math does support.
  static final RegExp _envOpen = RegExp(
      r'\\begin\{(align\*?|gather\*?|eqnarray\*?|split|multline\*?)\}');
  static final RegExp _envClose = RegExp(
      r'\\end\{(align\*?|gather\*?|eqnarray\*?|split|multline\*?)\}');

  @override
  Widget build(BuildContext context) {
    final cleaned = _clean(text);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _math.allMatches(cleaned)) {
      if (m.start > last) {
        spans.addAll(_prose(context, cleaned.substring(last, m.start)));
      }
      final latex =
          (m.group(1) ?? m.group(2) ?? m.group(3) ?? m.group(4) ?? '').trim();
      if (latex.isNotEmpty) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _mathWidget(context, latex),
        ));
      }
      last = m.end;
    }
    if (last < cleaned.length) {
      spans.addAll(_prose(context, cleaned.substring(last)));
    }
    if (spans.isEmpty) spans.add(const TextSpan(text: ''));

    return Text.rich(TextSpan(style: style, children: spans));
  }

  /// A rendered equation: renders LaTeX, scrolls horizontally if wide, and
  /// degrades to sanitised plain text (never raw markup) if the LaTeX is bad.
  Widget _mathWidget(BuildContext context, String latex) {
    final maxMath = MediaQuery.sizeOf(context).width * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxMath),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          _normalizeEnv(latex),
          textStyle: style,
          mathStyle: MathStyle.text,
          onErrorFallback: (_) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxMath),
            child: Text(_sanitizeFallback(latex), style: style),
          ),
        ),
      ),
    );
  }

  /// A prose run → spans, rendering any bare LaTeX commands as math and the rest
  /// as text (bold-aware, stray `$` dropped).
  List<InlineSpan> _prose(BuildContext context, String run) {
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _bareLatex.allMatches(run)) {
      if (m.start > last) out.addAll(_textSpans(run.substring(last, m.start)));
      out.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _mathWidget(context, m.group(0)!),
      ));
      last = m.end;
    }
    if (last < run.length) out.addAll(_textSpans(run.substring(last)));
    return out;
  }

  /// Plain prose → text spans: honour `**bold**`, and drop stray math `$`
  /// (but keep a `$` that fronts a number, i.e. money).
  List<InlineSpan> _textSpans(String run) {
    final text = run.replaceAll(RegExp(r'\$(?!\d)'), '');
    if (text.isEmpty) return const [];
    final out = <InlineSpan>[];
    var last = 0;
    for (final m in _bold.allMatches(text)) {
      if (m.start > last) out.add(TextSpan(text: text.substring(last, m.start)));
      out.add(TextSpan(
        text: m.group(1) ?? m.group(2),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ));
      last = m.end;
    }
    if (last < text.length) out.add(TextSpan(text: text.substring(last)));
    return out;
  }

  /// Strip markup with no place in a tutor bubble — but keep the substance.
  static String _clean(String s) {
    // Unwrap fenced code blocks (keep the inner text — often the actual working),
    // dropping an optional language tag; then remove any stray fence markers.
    var t = s.replaceAllMapped(
        RegExp(r'```[^\n]*\n?([\s\S]*?)```'), (m) => m.group(1) ?? '');
    t = t.replaceAll('```', '').replaceAll('`', '');
    // Real headings need a space after the hashes, so "#3" (an ordinal) survives.
    t = t.replaceAll(RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true), '');
    // Only turn "- "/"* " into bullets when it is genuinely a list (≥2 markers),
    // so a lone leading "- 5" (a negative number) or "* " (multiply) is kept.
    final bullet = RegExp(r'^\s*[-*]\s+', multiLine: true);
    if (bullet.allMatches(t).length >= 2) t = t.replaceAll(bullet, '• ');
    return t.trim();
  }

  static String _normalizeEnv(String s) => s
      .replaceAll(_envOpen, r'\begin{aligned}')
      .replaceAll(_envClose, r'\end{aligned}');

  /// Last-resort readable text for LaTeX flutter_math can't parse — strips the
  /// control tokens so a bubble never shows `\begin`, `&`, `\\` or backslash
  /// macros verbatim (e.g. `\begin{align} x+y &= 3 \\ x-y &= 1` → `x+y = 3 x-y = 1`).
  static String _sanitizeFallback(String s) => s
      .replaceAll(RegExp(r'\\(begin|end)\{[^}]*\}'), '')
      .replaceAll(r'\\', '  ')
      .replaceAll('&', ' ')
      .replaceAll(RegExp(r'\\[a-zA-Z]+'), '')
      .replaceAll(RegExp(r'[{}]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
