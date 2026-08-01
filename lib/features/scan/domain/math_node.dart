/// The editable document model behind the structured math field.
///
/// A [MathExpression] is an ordered list of [MathNode]s. A node is either a
/// leaf [MathAtom] (a digit, letter, operator or symbol) or a [MathTemplateNode]
/// — a structure such as a fraction, a root or an integral that owns its own
/// child expressions ("slots"). **An empty slot is what the UI draws as a
/// dashed box**, and what the caret can be moved into.
///
/// The model is deliberately mutable: editing a math field is a stream of small
/// in-place mutations (insert a node, delete the node before the caret) driven
/// by `MathFieldController`, and rebuilding an immutable tree on every keypress
/// would buy nothing here.
///
/// LaTeX is the only thing that ever leaves this layer — [MathExpression.toLatex]
/// is what feeds the existing recognize → solve pipeline, so the structured
/// editor is invisible to the backend contract.
library;

import 'math_templates.dart';

/// How an atom should be drawn.
enum MathAtomRender {
  /// A plain glyph drawn as text — digits, letters, operators, `π`, `∞`.
  text,

  /// An upright multi-letter operator name (`sin`, `log`, `sign`) — same as
  /// [text] but never italicised.
  operatorName,

  /// Anything the glyph map can't express, drawn by flutter_math from its raw
  /// LaTeX. Used for commands the parser met but doesn't model structurally.
  tex,
}

/// An ordered run of nodes — the whole document, or one slot of a template.
class MathExpression {
  MathExpression([List<MathNode>? nodes]) : nodes = nodes ?? <MathNode>[];

  /// Builds an expression of single-character atoms.
  factory MathExpression.chars(String text) =>
      MathExpression(text.split('').map(MathAtom.char).toList());

  final List<MathNode> nodes;

  bool get isEmpty => nodes.isEmpty;
  bool get isNotEmpty => nodes.isNotEmpty;

  /// The LaTeX for this run, concatenated in order.
  String toLatex() => nodes.map((n) => n.toLatex()).join();

  /// True when this run — or anything nested inside it — still has a slot the
  /// user hasn't filled in. Submitting with an empty box is a mistake, not a
  /// problem to solve, so validation blocks it with a specific message.
  bool get hasEmptySlot => nodes.any((n) => n.hasEmptySlot);

  /// True once there is at least one digit or letter somewhere in the tree.
  bool get hasContent => nodes.any((n) => n.hasContent);

  MathExpression copy() => MathExpression(nodes.map((n) => n.copy()).toList());

  @override
  String toString() => toLatex();
}

/// A single element of an expression.
sealed class MathNode {
  const MathNode();

  String toLatex();
  bool get hasEmptySlot;
  bool get hasContent;
  MathNode copy();
}

/// A leaf: one glyph (or one symbol command) with no editable children.
class MathAtom extends MathNode {
  const MathAtom({
    required this.latex,
    required this.display,
    this.render = MathAtomRender.text,
  });

  /// A plain ASCII character — digit, letter, operator, bracket.
  factory MathAtom.char(String c) => MathAtom(latex: c, display: c);

  /// A named operator such as `\sin` used without an argument. Names LaTeX
  /// doesn't define (`arcsec`, `arsinh`) go through `\operatorname{…}` so the
  /// emitted LaTeX still compiles.
  factory MathAtom.operatorName(String name) => MathAtom(
        latex: '${MathTemplates.commandFor(name)} ',
        display: name,
        render: MathAtomRender.operatorName,
      );

  /// A LaTeX command the parser could not model — kept verbatim so editing a
  /// recognized equation never silently drops part of it, and drawn by
  /// flutter_math so it still *looks* right.
  factory MathAtom.raw(String latex, {String? display}) => MathAtom(
        latex: latex,
        display: display ?? latex,
        render: MathAtomRender.tex,
      );

  /// What this atom contributes to the LaTeX output.
  final String latex;

  /// The glyph shown in the field and on the key face.
  final String display;

  final MathAtomRender render;

  /// Hoisted: `hasContent` walks the whole tree on every keystroke, and a
  /// per-call `RegExp(…)` there is pure allocation.
  static final RegExp _contentful = RegExp(r'[0-9A-Za-z]');

  @override
  String toLatex() => latex;

  @override
  bool get hasEmptySlot => false;

  @override
  bool get hasContent => _contentful.hasMatch(display);

  @override
  MathAtom copy() => this; // immutable

  @override
  String toString() => display;
}

/// A structure with editable child slots — `\frac{□}{□}`, `\sqrt{□}`,
/// `\int_{□}^{□} □ \,d□` …
class MathTemplateNode extends MathNode {
  MathTemplateNode(this.template, [List<MathExpression>? slots])
      : slots = slots ??
            List.generate(template.slotCount, (_) => MathExpression(),
                growable: false);

  /// Builds a node whose slots are pre-filled with single-character atoms.
  factory MathTemplateNode.filled(MathTemplate template, List<String> slots) =>
      MathTemplateNode(
        template,
        List.generate(
          template.slotCount,
          (i) => i < slots.length
              ? MathExpression.chars(slots[i])
              : MathExpression(),
          growable: false,
        ),
      );

  final MathTemplate template;
  final List<MathExpression> slots;

  @override
  String toLatex() =>
      template.toLatex(slots.map((s) => s.toLatex()).toList(growable: false));

  @override
  bool get hasEmptySlot =>
      slots.any((s) => s.isEmpty || s.hasEmptySlot);

  @override
  bool get hasContent =>
      template.hasOwnContent || slots.any((s) => s.hasContent);

  @override
  MathTemplateNode copy() => MathTemplateNode(
        template,
        slots.map((s) => s.copy()).toList(growable: false),
      );

  @override
  String toString() => toLatex();
}
