/// Typesetting of a [MathPart] tree.
///
/// This is the one place that knows how a fraction, a radical or a matrix is
/// drawn. It is deliberately independent of *what* is being drawn: a slot is
/// rendered by the caller's [MathSlotBuilder], so the very same code lays out
/// an editable expression in the field and the miniature preview on a keyboard
/// key. That is what makes a key face an honest picture of what tapping it
/// produces.
library;

import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../domain/math_node.dart';
import '../../domain/math_templates.dart';

/// Font size, colour and script depth at one point in the tree.
@immutable
class MathRenderStyle {
  const MathRenderStyle({
    required this.fontSize,
    required this.color,
    this.scriptLevel = 0,
  });

  final double fontSize;
  final Color color;

  /// How deep in superscripts / limits / indices we are — each level shrinks.
  final int scriptLevel;

  /// The style for a script, index or limit of this one.
  MathRenderStyle get script => MathRenderStyle(
        fontSize: (fontSize * 0.7).clamp(11.0, fontSize),
        color: color,
        scriptLevel: scriptLevel + 1,
      );

  MathRenderStyle withColor(Color c) =>
      MathRenderStyle(fontSize: fontSize, color: c, scriptLevel: scriptLevel);

  /// Line thickness for fraction bars, radical bars and overlines.
  double get rule => (fontSize * 0.055).clamp(1.0, 2.0);
}

/// Renders the slot at [index] — an editable expression in the field, a dashed
/// box on a key face.
typedef MathSlotBuilder = Widget Function(int index, MathRenderStyle style);

/// Operators that are drawn oversized.
const _bigOperators = {'∫', '∬', '∮', '∑', '∏'};

/// Draws one [MathPart].
class MathPartView extends StatelessWidget {
  const MathPartView({
    super.key,
    required this.part,
    required this.style,
    required this.slotBuilder,
  });

  final MathPart part;
  final MathRenderStyle style;
  final MathSlotBuilder slotBuilder;

  Widget _child(MathPart p, MathRenderStyle s) =>
      MathPartView(part: p, style: s, slotBuilder: slotBuilder);

  @override
  Widget build(BuildContext context) {
    final p = part;
    return switch (p) {
      MathSlotPart() => slotBuilder(p.index, style),
      MathGlyphPart() => MathGlyph(text: p.text, style: style, upright: p.upright),
      MathRowPart() => Row(
          mainAxisSize: MainAxisSize.min,
          children: [for (final c in p.parts) _child(c, style)],
        ),
      MathFracPart() => MathFraction(
          numerator: _child(p.top, style),
          denominator: _child(p.bottom, style),
          style: style,
        ),
      MathRadicalPart() => MathRadical(
          radicand: _child(p.radicand, style),
          index: p.index == null ? null : _child(p.index!, style.script),
          style: style,
        ),
      MathScriptPart() => MathScripts(
          base: _child(p.base, style),
          sup: p.sup == null ? null : _child(p.sup!, style.script),
          sub: p.sub == null ? null : _child(p.sub!, style.script),
          style: style,
        ),
      MathLoneScriptPart() => MathScripts(
          base: const SizedBox.shrink(),
          sup: p.raised ? _child(p.child, style.script) : null,
          sub: p.raised ? null : _child(p.child, style.script),
          style: style,
        ),
      MathDelimitedPart() => MathDelimited(
          left: p.left,
          right: p.right,
          style: style,
          child: _child(p.child, style),
        ),
      MathLimitsPart() => MathLimits(
          base: _child(p.base, style),
          under: p.under == null ? null : _child(p.under!, style.script),
          over: p.over == null ? null : _child(p.over!, style.script),
          inline: p.inline,
        ),
      MathOverlinePart() => MathOverline(
          style: style,
          child: _child(p.child, style),
        ),
      MathGridPart() => MathGrid(
          left: p.left,
          right: p.right,
          style: style,
          rows: [
            for (final row in p.rows) [for (final cell in row) _child(cell, style)],
          ],
        ),
    };
  }
}

/// A run of glyphs — digits, operators, variable letters, operator names.
class MathGlyph extends StatelessWidget {
  const MathGlyph({
    super.key,
    required this.text,
    required this.style,
    this.upright = false,
  });

  final String text;
  final MathRenderStyle style;
  final bool upright;

  static final RegExp _latin = RegExp(r'[A-Za-z]');

  /// Single Latin letters are variables, and variables are italic.
  static bool isVariable(String s) => s.length == 1 && _latin.hasMatch(s);

  @override
  Widget build(BuildContext context) {
    final big = text.length == 1 && _bigOperators.contains(text);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _spacing(text) * style.fontSize,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: big ? style.fontSize * 1.5 : style.fontSize,
          height: 1.1,
          color: style.color,
          fontStyle: !upright && isVariable(text)
              ? FontStyle.italic
              : FontStyle.normal,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  /// Binary operators and relations breathe; everything else is tight.
  static double _spacing(String s) {
    if (s.length != 1) return 0.02;
    if ('+−-=×÷·<>≤≥≠≈→±∓'.contains(s)) return 0.10;
    if (','.contains(s)) return 0.02;
    return 0.01;
  }
}

/// A leaf of the document tree drawn as text, or via flutter_math when it is
/// raw LaTeX we couldn't model.
class MathAtomView extends StatelessWidget {
  const MathAtomView({super.key, required this.atom, required this.style});

  final MathAtom atom;
  final MathRenderStyle style;

  @override
  Widget build(BuildContext context) {
    if (atom.render == MathAtomRender.tex) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: style.fontSize * 0.02),
        child: Math.tex(
          atom.latex,
          textStyle: TextStyle(fontSize: style.fontSize, color: style.color),
          onErrorFallback: (_) => MathGlyph(
            text: atom.display,
            style: style,
            upright: true,
          ),
        ),
      );
    }
    return MathGlyph(
      text: atom.display,
      style: style,
      upright: atom.render == MathAtomRender.operatorName,
    );
  }
}

/// Numerator over denominator, with the rule spanning the wider of the two.
class MathFraction extends StatelessWidget {
  const MathFraction({
    super.key,
    required this.numerator,
    required this.denominator,
    required this.style,
  });

  final Widget numerator;
  final Widget denominator;
  final MathRenderStyle style;

  @override
  Widget build(BuildContext context) {
    final gap = style.fontSize * 0.10;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: style.fontSize * 0.08),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: numerator),
            Padding(
              padding: EdgeInsets.symmetric(vertical: gap),
              child: Container(height: style.rule, color: style.color),
            ),
            Center(child: denominator),
          ],
        ),
      ),
    );
  }
}

/// √ with a bar that spans the radicand, and an optional index in the crook.
class MathRadical extends StatelessWidget {
  const MathRadical({
    super.key,
    required this.radicand,
    required this.style,
    this.index,
  });

  final Widget radicand;
  final Widget? index;
  final MathRenderStyle style;

  @override
  Widget build(BuildContext context) {
    final hookWidth = style.fontSize * 0.42;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (index != null)
          Padding(
            padding: EdgeInsets.only(bottom: style.fontSize * 0.55),
            child: index,
          ),
        CustomPaint(
          painter: _RadicalPainter(
            color: style.color,
            hookWidth: hookWidth,
            rule: style.rule,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: hookWidth + style.fontSize * 0.06,
              top: style.rule + style.fontSize * 0.12,
              right: style.fontSize * 0.10,
              bottom: style.fontSize * 0.04,
            ),
            child: radicand,
          ),
        ),
      ],
    );
  }
}

class _RadicalPainter extends CustomPainter {
  const _RadicalPainter({
    required this.color,
    required this.hookWidth,
    required this.rule,
  });

  final Color color;
  final double hookWidth;
  final double rule;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = rule
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.60)
      ..lineTo(hookWidth * 0.30, h * 0.52)
      ..lineTo(hookWidth * 0.62, h - rule)
      ..lineTo(hookWidth * 0.95, rule / 2)
      ..lineTo(size.width, rule / 2);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_RadicalPainter old) =>
      old.color != color || old.hookWidth != hookWidth || old.rule != rule;
}

/// A base carrying a superscript and/or a subscript.
///
/// The composite is padded symmetrically so its vertical centre stays on the
/// *base's* centre — otherwise every `x²` in a row would ride visibly high
/// against its neighbours.
class MathScripts extends StatelessWidget {
  const MathScripts({
    super.key,
    required this.base,
    required this.style,
    this.sup,
    this.sub,
  });

  final Widget base;
  final Widget? sup;
  final Widget? sub;
  final MathRenderStyle style;

  @override
  Widget build(BuildContext context) {
    final shift = style.fontSize * 0.46;

    if (sup != null && sub != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          base,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [sup!, SizedBox(height: style.fontSize * 0.12), sub!],
          ),
        ],
      );
    }
    if (sup != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: shift),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: EdgeInsets.only(top: shift), child: base),
            sup!,
          ],
        ),
      );
    }
    if (sub != null) {
      return Padding(
        padding: EdgeInsets.only(top: shift),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(padding: EdgeInsets.only(bottom: shift), child: base),
            sub!,
          ],
        ),
      );
    }
    return base;
  }
}

/// Brackets that grow with what they hold.
class MathDelimited extends StatelessWidget {
  const MathDelimited({
    super.key,
    required this.child,
    required this.style,
    this.left = '(',
    this.right = ')',
  });

  final Widget child;
  final MathRenderStyle style;
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MathDelimiter(shape: left, style: style, opening: true),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: style.fontSize * 0.04),
            child: Center(child: child),
          ),
          MathDelimiter(shape: right, style: style, opening: false),
        ],
      ),
    );
  }
}

/// One growing bracket, drawn rather than typeset so it matches any height.
class MathDelimiter extends StatelessWidget {
  const MathDelimiter({
    super.key,
    required this.shape,
    required this.style,
    required this.opening,
  });

  final String shape;
  final MathRenderStyle style;
  final bool opening;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: shape == '|' ? style.fontSize * 0.24 : style.fontSize * 0.30,
      child: CustomPaint(
        painter: _DelimiterPainter(
          shape: shape,
          opening: opening,
          color: style.color,
          rule: style.rule,
        ),
      ),
    );
  }
}

class _DelimiterPainter extends CustomPainter {
  const _DelimiterPainter({
    required this.shape,
    required this.opening,
    required this.color,
    required this.rule,
  });

  final String shape;
  final bool opening;
  final Color color;
  final double rule;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = rule
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final inset = rule / 2;
    final path = Path();
    switch (shape) {
      case '|':
        path
          ..moveTo(w / 2, inset)
          ..lineTo(w / 2, h - inset);
      case '[':
      case ']':
        final x = opening ? w * 0.65 : w * 0.35;
        final tip = opening ? w * 0.15 : w * 0.85;
        path
          ..moveTo(tip, inset)
          ..lineTo(x, inset)
          ..moveTo(x, inset)
          ..lineTo(x, h - inset)
          ..moveTo(x, h - inset)
          ..lineTo(tip, h - inset);
        // Vertical stroke plus the two serifs.
        path
          ..moveTo(opening ? w * 0.28 : w * 0.72, inset)
          ..lineTo(opening ? w * 0.28 : w * 0.72, h - inset);
      case '{':
      case '}':
        final dir = opening ? 1.0 : -1.0;
        final cx = w / 2 - dir * w * 0.1;
        path
          ..moveTo(cx + dir * w * 0.45, inset)
          ..quadraticBezierTo(cx, inset, cx, h * 0.28)
          ..quadraticBezierTo(cx, h * 0.5, cx - dir * w * 0.35, h * 0.5)
          ..quadraticBezierTo(cx, h * 0.5, cx, h * 0.72)
          ..quadraticBezierTo(cx, h - inset, cx + dir * w * 0.45, h - inset);
      default:
        // Parenthesis.
        final dir = opening ? 1.0 : -1.0;
        final near = w / 2 - dir * w * 0.22;
        final far = w / 2 + dir * w * 0.34;
        path
          ..moveTo(far, inset)
          ..quadraticBezierTo(near, h * 0.5, far, h - inset);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DelimiterPainter old) =>
      old.shape != shape ||
      old.opening != opening ||
      old.color != color ||
      old.rule != rule;
}

/// A big operator with limits — `lim` and `∑` stack them, `∫` sets them beside.
class MathLimits extends StatelessWidget {
  const MathLimits({
    super.key,
    required this.base,
    this.under,
    this.over,
    this.inline = false,
  });

  final Widget base;
  final Widget? under;
  final Widget? over;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    if (inline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          base,
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [?over, ?under],
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [?over, base, ?under],
    );
  }
}

/// A bar over the child — complex conjugate.
class MathOverline extends StatelessWidget {
  const MathOverline({super.key, required this.child, required this.style});

  final Widget child;
  final MathRenderStyle style;

  @override
  Widget build(BuildContext context) {
    final gap = style.fontSize * 0.08;
    return Padding(
      padding: EdgeInsets.only(bottom: style.rule + gap),
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(height: style.rule, color: style.color),
            SizedBox(height: gap),
            Center(child: child),
          ],
        ),
      ),
    );
  }
}

/// A bracketed grid — matrices, determinants, column vectors.
class MathGrid extends StatelessWidget {
  const MathGrid({
    super.key,
    required this.rows,
    required this.style,
    this.left = '[',
    this.right = ']',
  });

  final List<List<Widget>> rows;
  final MathRenderStyle style;
  final String left;
  final String right;

  @override
  Widget build(BuildContext context) {
    final pad = style.fontSize * 0.16;
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MathDelimiter(shape: left, style: style, opening: true),
          IntrinsicWidth(
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                for (final row in rows)
                  TableRow(
                    children: [
                      for (final cell in row)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: pad,
                            vertical: pad * 0.5,
                          ),
                          child: Center(child: cell),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          MathDelimiter(shape: right, style: style, opening: false),
        ],
      ),
    );
  }
}

/// The dashed box that stands for an empty slot — the thing that makes the
/// keyboard's structured keys legible: a key shows the boxes you are about to
/// get, and the field shows the boxes still waiting to be filled.
class MathPlaceholderBox extends StatelessWidget {
  const MathPlaceholderBox({
    super.key,
    required this.style,
    this.active = false,
    this.activeColor,
    this.child,
  });

  final MathRenderStyle style;

  /// Whether the caret is inside this box — drawn solid and tinted.
  final bool active;

  /// The accent the box takes on while the caret is in it. Without it an
  /// active box only darkens, which on a page of four identical boxes is not
  /// enough to say "this is the one you are filling".
  final Color? activeColor;

  /// The caret, when it is inside.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final size = style.fontSize * 0.62;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: style.fontSize * 0.05),
      child: CustomPaint(
        painter: _DashedBoxPainter(
          color: active
              ? (activeColor ?? style.color).withValues(alpha: 0.95)
              : style.color.withValues(alpha: 0.5),
          rule: active ? style.rule * 1.4 : style.rule,
          dashed: !active,
        ),
        child: SizedBox(
          width: size,
          height: size * 1.15,
          child: child == null ? null : Center(child: child),
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter({
    required this.color,
    required this.rule,
    required this.dashed,
  });

  final Color color;
  final double rule;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = rule
      ..style = PaintingStyle.stroke;
    final rect = Rect.fromLTWH(
      rule / 2,
      rule / 2,
      size.width - rule,
      size.height - rule,
    );
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(rule));
    if (!dashed) {
      canvas.drawRRect(rrect, paint);
      return;
    }
    const dash = 2.5;
    const gap = 2.0;
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) =>
      old.color != color || old.rule != rule || old.dashed != dashed;
}
