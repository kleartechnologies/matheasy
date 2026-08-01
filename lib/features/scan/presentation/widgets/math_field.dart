import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../application/math_field_controller.dart';
import '../../domain/math_node.dart';
import 'math_layout.dart';

/// The structured math input line — a WYSIWYG editor, not a text field.
///
/// What you see is the expression itself: fractions stacked, roots under a
/// radical, and **dashed boxes wherever a structure still needs a value**. The
/// caret lives in the tree rather than in a string, so tapping a box drops you
/// inside it and the arrow keys walk in and out of numerators, exponents and
/// limits.
///
/// It renders [MathFieldController.root] and reports taps back to the same
/// controller; it holds no editing state of its own.
class MathField extends StatefulWidget {
  const MathField({
    super.key,
    required this.controller,
    this.fontSize = 30,
    this.hint,
  });

  final MathFieldController controller;
  final double fontSize;

  /// Shown in place of the expression while the document is empty.
  final String? hint;

  @override
  State<MathField> createState() => _MathFieldState();
}

class _MathFieldState extends State<MathField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  final ScrollController _scroll = ScrollController();
  final GlobalKey _caretKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onEdit);
    _blink.repeat();
  }

  @override
  void didUpdateWidget(MathField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onEdit);
      widget.controller.addListener(_onEdit);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onEdit);
    _blink.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (!mounted) return;
    setState(() {});
    // Restart the blink so the caret is solid the instant you type — a caret
    // that happens to be mid-blink reads as "the key didn't register".
    _blink
      ..reset()
      ..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCaret());
  }

  void _revealCaret() {
    final context = _caretKey.currentContext;
    if (context == null || !mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.5,
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Respect the reader's text size, but cap it: this line is a single row of
    // math and unbounded growth would push the keyboard off-screen.
    final scaled = MediaQuery.textScalerOf(context)
        .scale(widget.fontSize)
        .clamp(widget.fontSize, widget.fontSize * 1.25);
    final style = MathRenderStyle(fontSize: scaled, color: colors.textPrimary);
    final controller = widget.controller;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // A tap on the empty space after the expression means "carry on typing".
      onTap: () => controller.placeCursor(const [], controller.root.nodes.length),
      child: SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: style.fontSize * 1.6),
          child: Row(
            children: [
              MathExpressionView(
                expression: controller.root,
                path: const [],
                controller: controller,
                style: style,
                blink: _blink,
                caretKey: _caretKey,
                hint: widget.hint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One editable run of nodes — the document, or a single slot of a template.
class MathExpressionView extends StatelessWidget {
  const MathExpressionView({
    super.key,
    required this.expression,
    required this.path,
    required this.controller,
    required this.style,
    required this.blink,
    required this.caretKey,
    this.hint,
  });

  final MathExpression expression;
  final List<MathStep> path;
  final MathFieldController controller;
  final MathRenderStyle style;
  final Animation<double> blink;

  /// Attached to the caret wherever it currently is, so the field can scroll
  /// it into view.
  final GlobalKey caretKey;

  /// Root-only placeholder text.
  final String? hint;

  bool get _cursorHere => controller.cursor.isIn(path);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final caretColor = colors.onPrimaryContainer;

    if (expression.isEmpty) {
      // The root shows a hint; a template's slot shows its dashed box.
      if (path.isEmpty) {
        return _TapTarget(
          onTapAt: (_, _) => controller.placeCursor(const [], 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_cursorHere)
                _Caret(
                  key: caretKey,
                  style: style,
                  color: caretColor,
                  blink: blink,
                ),
              if (hint != null)
                Text(
                  hint!,
                  style: TextStyle(
                    fontSize: style.fontSize * 0.6,
                    color: colors.textMuted,
                  ),
                ),
            ],
          ),
        );
      }
      return _TapTarget(
        onTapAt: (_, _) => controller.placeCursor(path, 0),
        child: MathPlaceholderBox(
          style: style,
          active: _cursorHere,
          activeColor: caretColor,
          child: _cursorHere
              ? _Caret(
                  key: caretKey,
                  style: style,
                  color: caretColor,
                  compact: true,
                  blink: blink,
                )
              : null,
        ),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i <= expression.nodes.length; i++) {
      if (_cursorHere && controller.cursor.offset == i) {
        children.add(
          _Caret(key: caretKey, style: style, color: caretColor, blink: blink),
        );
      }
      if (i == expression.nodes.length) break;
      children.add(
        _TapTarget(
          onTapAt: (dx, width) =>
              controller.placeCursor(path, dx < width / 2 ? i : i + 1),
          child: MathNodeView(
            node: expression.nodes[i],
            path: path,
            nodeIndex: i,
            controller: controller,
            style: style,
            blink: blink,
            caretKey: caretKey,
          ),
        ),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// One node: a glyph, or a template whose slots are themselves editable.
class MathNodeView extends StatelessWidget {
  const MathNodeView({
    super.key,
    required this.node,
    required this.path,
    required this.nodeIndex,
    required this.controller,
    required this.style,
    required this.blink,
    required this.caretKey,
  });

  final MathNode node;
  final List<MathStep> path;
  final int nodeIndex;
  final MathFieldController controller;
  final MathRenderStyle style;
  final Animation<double> blink;
  final GlobalKey caretKey;

  @override
  Widget build(BuildContext context) {
    final n = node;
    if (n is MathAtom) return MathAtomView(atom: n, style: style);

    final template = n as MathTemplateNode;
    return MathPartView(
      part: template.template.layout,
      style: style,
      slotBuilder: (slotIndex, slotStyle) => MathExpressionView(
        expression: template.slots[slotIndex],
        path: [...path, MathStep(nodeIndex, slotIndex)],
        controller: controller,
        style: slotStyle,
        blink: blink,
        caretKey: caretKey,
      ),
    );
  }
}

/// The blinking insertion point.
class _Caret extends StatelessWidget {
  const _Caret({
    super.key,
    required this.style,
    required this.color,
    required this.blink,
    this.compact = false,
  });

  final MathRenderStyle style;
  final Color color;
  final Animation<double> blink;

  /// Sized to sit inside a dashed placeholder box rather than beside glyphs.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      width: (style.fontSize * 0.06).clamp(1.5, 2.5),
      height: style.fontSize * (compact ? 0.72 : 1.15),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
    // A blinking caret is decorative motion — hold it steady for anyone who
    // has asked the system to reduce animation.
    if (MediaQuery.disableAnimationsOf(context)) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: style.fontSize * 0.02),
        child: bar,
      );
    }
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: style.fontSize * 0.02),
      child: FadeTransition(
        opacity: _CaretOpacity(blink),
        child: bar,
      ),
    );
  }
}

/// Square-wave opacity: solid for half the period, invisible for the rest.
class _CaretOpacity extends Animation<double>
    with AnimationWithParentMixin<double> {
  _CaretOpacity(this.parent);

  @override
  final Animation<double> parent;

  @override
  double get value => parent.value < 0.55 ? 1 : 0;
}

/// Reports where within the child a tap landed, so the caret can go before or
/// after the glyph you touched.
class _TapTarget extends StatelessWidget {
  const _TapTarget({required this.onTapAt, required this.child});

  final void Function(double dx, double width) onTapAt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (inner) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final box = inner.findRenderObject() as RenderBox?;
          onTapAt(details.localPosition.dx, box?.size.width ?? 1);
        },
        child: child,
      ),
    );
  }
}
