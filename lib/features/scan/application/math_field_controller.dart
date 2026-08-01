import 'package:flutter/foundation.dart';

import '../domain/math_latex_parser.dart';
import '../domain/math_node.dart';
import '../domain/math_templates.dart';

/// One descent into a template: "the slot at [slotIndex] of the node at
/// [nodeIndex]".
@immutable
class MathStep {
  const MathStep(this.nodeIndex, this.slotIndex);
  final int nodeIndex;
  final int slotIndex;

  @override
  bool operator ==(Object other) =>
      other is MathStep &&
      other.nodeIndex == nodeIndex &&
      other.slotIndex == slotIndex;

  @override
  int get hashCode => Object.hash(nodeIndex, slotIndex);

  @override
  String toString() => '$nodeIndex.$slotIndex';
}

/// Where the caret is: a [path] of descents from the root, plus the insertion
/// [offset] within the expression that path lands on (`0…nodes.length`).
@immutable
class MathCursor {
  const MathCursor(this.path, this.offset);

  static const MathCursor start = MathCursor(<MathStep>[], 0);

  final List<MathStep> path;
  final int offset;

  /// Whether the caret sits inside the expression identified by [other].
  bool isIn(List<MathStep> other) => listEquals(path, other);

  @override
  bool operator ==(Object other) =>
      other is MathCursor &&
      other.offset == offset &&
      listEquals(other.path, path);

  @override
  int get hashCode => Object.hash(Object.hashAll(path), offset);

  @override
  String toString() => '${path.join('/')}@$offset';
}

/// The editing brain of the structured math field.
///
/// Owns the document ([root]) and the caret ([cursor]), and exposes the small
/// set of operations the keyboard drives: insert, backspace, move, and place
/// the caret from a tap. Every mutation notifies listeners, which is what
/// repaints the field and re-runs validation.
///
/// The controller never talks to the network and never sees a solve — its only
/// output is [latex], which feeds the existing recognize → solve pipeline
/// unchanged.
class MathFieldController extends ChangeNotifier {
  MathFieldController({String? initialLatex}) {
    if (initialLatex != null && initialLatex.trim().isNotEmpty) {
      _root = MathLatexParser.parse(initialLatex);
      _cursor = MathCursor(const [], _root.nodes.length);
    }
  }

  MathExpression _root = MathExpression();
  MathCursor _cursor = MathCursor.start;

  MathExpression get root => _root;
  MathCursor get cursor => _cursor;

  /// The document as LaTeX — the contract with everything downstream.
  String get latex => _root.toLatex();

  bool get isEmpty => _root.isEmpty;

  /// True while any dashed box anywhere is still unfilled.
  bool get hasEmptySlot => _root.hasEmptySlot;

  /// True once there's an actual number or variable to work with.
  bool get hasContent => _root.hasContent;

  /// Replaces the whole document, parsing [latex] back into a tree so a
  /// recognized equation stays *editable* rather than becoming opaque text.
  void setLatex(String latex) {
    _root = MathLatexParser.parse(latex);
    _cursor = MathCursor(const [], _root.nodes.length);
    notifyListeners();
  }

  void clear() {
    _root = MathExpression();
    _cursor = MathCursor.start;
    notifyListeners();
  }

  /// Moves the caret to an explicit position — how a tap on the field lands.
  void placeCursor(List<MathStep> path, int offset) {
    final target = _resolveOrNull(path);
    if (target == null) return;
    _cursor = MathCursor(
      List<MathStep>.unmodifiable(path),
      offset.clamp(0, target.nodes.length),
    );
    notifyListeners();
  }

  // -- Insertion ------------------------------------------------------------

  /// Inserts a leaf glyph at the caret.
  void insertAtom(MathAtom atom) {
    final target = _resolve(_cursor.path);
    target.nodes.insert(_cursor.offset, atom);
    _cursor = MathCursor(_cursor.path, _cursor.offset + 1);
    notifyListeners();
  }

  /// Inserts a structured template and drops the caret into its first slot —
  /// tapping `□/□` should leave you typing the numerator, not stranded after it.
  void insertTemplate(MathTemplate template) {
    final target = _resolve(_cursor.path);
    final node = MathTemplateNode(template);
    final at = _cursor.offset;
    target.nodes.insert(at, node);
    if (template.slotCount > 0) {
      _cursor = MathCursor([..._cursor.path, MathStep(at, 0)], 0);
    } else {
      _cursor = MathCursor(_cursor.path, at + 1);
    }
    notifyListeners();
  }

  /// Wraps whatever precedes the caret — the last "operand" — in [template]'s
  /// first slot: typing `12` then `x²` gives `12²`, the way a calculator
  /// behaves when you hit `x²` after a number, rather than leaving an empty box
  /// beside what you just typed. Falls back to a plain insert when the caret
  /// isn't sitting after an operand.
  void applyToPrevious(MathTemplate template) {
    if (template.slotCount == 0) {
      insertTemplate(template);
      return;
    }
    final target = _resolve(_cursor.path);
    final start = _operandStart(target.nodes, _cursor.offset);
    if (start == _cursor.offset) {
      insertTemplate(template);
      return;
    }
    final taken = target.nodes.sublist(start, _cursor.offset);
    target.nodes.removeRange(start, _cursor.offset);
    final node = MathTemplateNode(template)
      ..slots[0].nodes.addAll(taken);
    target.nodes.insert(start, node);
    // Caret into the *second* slot when there is one (the exponent you're about
    // to type); otherwise just after the wrapped node.
    if (template.slotCount > 1) {
      _cursor = MathCursor([..._cursor.path, MathStep(start, 1)], 0);
    } else {
      _cursor = MathCursor(_cursor.path, start + 1);
    }
    notifyListeners();
  }

  static final RegExp _digit = RegExp(r'[0-9.]');
  static final RegExp _letter = RegExp(r'[A-Za-z]');

  /// The index where the operand ending at [end] begins — a run of digits or a
  /// single symbol/template, plus any bracketed group.
  int _operandStart(List<MathNode> nodes, int end) {
    if (end <= 0) return end;
    final prev = nodes[end - 1];
    if (prev is MathTemplateNode) return end - 1;
    if (prev is MathAtom) {
      if (!_digit.hasMatch(prev.display)) {
        // A letter or symbol on its own; an operator is not an operand.
        return _letter.hasMatch(prev.display) ? end - 1 : end;
      }
      var i = end - 1;
      while (i > 0) {
        final n = nodes[i - 1];
        if (n is MathAtom && _digit.hasMatch(n.display)) {
          i--;
        } else {
          break;
        }
      }
      return i;
    }
    return end;
  }

  // -- Deletion -------------------------------------------------------------

  void backspace() {
    final path = _cursor.path;
    final target = _resolve(path);

    if (_cursor.offset > 0) {
      final prev = target.nodes[_cursor.offset - 1];
      if (prev is MathTemplateNode && prev.slots.any((s) => s.isNotEmpty)) {
        // Don't nuke a filled structure in one tap — step inside it instead.
        final slotIndex = prev.slots.lastIndexWhere((s) => s.isNotEmpty);
        _cursor = MathCursor(
          [...path, MathStep(_cursor.offset - 1, slotIndex)],
          prev.slots[slotIndex].nodes.length,
        );
      } else {
        target.nodes.removeAt(_cursor.offset - 1);
        _cursor = MathCursor(path, _cursor.offset - 1);
      }
      notifyListeners();
      return;
    }

    // At the start of a slot: step out, deleting the structure if it's empty.
    if (path.isEmpty) return;
    final last = path.last;
    final parentPath = path.sublist(0, path.length - 1);
    final parent = _resolve(parentPath);
    final node = parent.nodes[last.nodeIndex] as MathTemplateNode;

    if (node.slots.every((s) => s.isEmpty)) {
      parent.nodes.removeAt(last.nodeIndex);
      _cursor = MathCursor(parentPath, last.nodeIndex);
    } else if (last.slotIndex > 0) {
      final prevSlot = node.slots[last.slotIndex - 1];
      _cursor = MathCursor(
        [...parentPath, MathStep(last.nodeIndex, last.slotIndex - 1)],
        prevSlot.nodes.length,
      );
    } else {
      _cursor = MathCursor(parentPath, last.nodeIndex);
    }
    notifyListeners();
  }

  // -- Caret movement -------------------------------------------------------

  void moveLeft() {
    final path = _cursor.path;
    final target = _resolve(path);

    if (_cursor.offset > 0) {
      final prev = target.nodes[_cursor.offset - 1];
      if (prev is MathTemplateNode && prev.slots.isNotEmpty) {
        final slotIndex = prev.slots.length - 1;
        _cursor = MathCursor(
          [...path, MathStep(_cursor.offset - 1, slotIndex)],
          prev.slots[slotIndex].nodes.length,
        );
      } else {
        _cursor = MathCursor(path, _cursor.offset - 1);
      }
      notifyListeners();
      return;
    }

    if (path.isEmpty) return;
    final last = path.last;
    final parentPath = path.sublist(0, path.length - 1);
    if (last.slotIndex > 0) {
      final parent = _resolve(parentPath);
      final node = parent.nodes[last.nodeIndex] as MathTemplateNode;
      _cursor = MathCursor(
        [...parentPath, MathStep(last.nodeIndex, last.slotIndex - 1)],
        node.slots[last.slotIndex - 1].nodes.length,
      );
    } else {
      _cursor = MathCursor(parentPath, last.nodeIndex);
    }
    notifyListeners();
  }

  void moveRight() {
    final path = _cursor.path;
    final target = _resolve(path);

    if (_cursor.offset < target.nodes.length) {
      final next = target.nodes[_cursor.offset];
      if (next is MathTemplateNode && next.slots.isNotEmpty) {
        _cursor = MathCursor([...path, MathStep(_cursor.offset, 0)], 0);
      } else {
        _cursor = MathCursor(path, _cursor.offset + 1);
      }
      notifyListeners();
      return;
    }

    if (path.isEmpty) return;
    final last = path.last;
    final parentPath = path.sublist(0, path.length - 1);
    final parent = _resolve(parentPath);
    final node = parent.nodes[last.nodeIndex] as MathTemplateNode;
    if (last.slotIndex < node.slots.length - 1) {
      _cursor = MathCursor(
        [...parentPath, MathStep(last.nodeIndex, last.slotIndex + 1)],
        0,
      );
    } else {
      _cursor = MathCursor(parentPath, last.nodeIndex + 1);
    }
    notifyListeners();
  }

  /// Jumps to the next empty box, wrapping around — the fastest way to fill a
  /// freshly-inserted template with several slots.
  bool moveToNextEmptySlot() {
    final found = _findEmptySlot(_root, const <MathStep>[]);
    if (found == null) return false;
    _cursor = found;
    notifyListeners();
    return true;
  }

  MathCursor? _findEmptySlot(MathExpression expr, List<MathStep> path) {
    for (var i = 0; i < expr.nodes.length; i++) {
      final node = expr.nodes[i];
      if (node is! MathTemplateNode) continue;
      for (var s = 0; s < node.slots.length; s++) {
        final childPath = [...path, MathStep(i, s)];
        if (node.slots[s].isEmpty) return MathCursor(childPath, 0);
        final deeper = _findEmptySlot(node.slots[s], childPath);
        if (deeper != null) return deeper;
      }
    }
    return null;
  }

  // -- Path resolution ------------------------------------------------------

  MathExpression _resolve(List<MathStep> path) =>
      _resolveOrNull(path) ?? _fallbackToRoot();

  MathExpression _fallbackToRoot() {
    _cursor = MathCursor(const [], _root.nodes.length);
    return _root;
  }

  MathExpression? _resolveOrNull(List<MathStep> path) {
    var expr = _root;
    for (final step in path) {
      if (step.nodeIndex < 0 || step.nodeIndex >= expr.nodes.length) return null;
      final node = expr.nodes[step.nodeIndex];
      if (node is! MathTemplateNode) return null;
      if (step.slotIndex < 0 || step.slotIndex >= node.slots.length) return null;
      expr = node.slots[step.slotIndex];
    }
    return expr;
  }
}
