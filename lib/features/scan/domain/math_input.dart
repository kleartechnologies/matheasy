/// Validation for a typed math problem (manual entry) before it is handed to
/// the same recognize → solve pipeline a scanned problem uses.
///
/// Deliberately lenient: it only blocks input that would clearly waste a solve
/// (empty, unbalanced brackets, no actual math). The solver / AI tutor handle
/// everything else, exactly as they do for a scanned equation.
class MathInput {
  const MathInput._();

  static const String emptyMessage = 'Type a problem to solve.';
  static const String noContentMessage = 'Add some numbers or variables.';
  static const String unbalancedMessage =
      "Check your brackets — something isn't closed.";

  /// Shown when a structure the user opened still has a dashed box waiting for
  /// a value. Submitting `\frac{}{}` isn't a problem to solve — it's a slip —
  /// and saying so beats spending a scan on a "couldn't verify".
  static const String emptyBoxMessage = 'Fill in the empty boxes first.';

  /// Returns a short, user-facing error, or `null` when the input is good to
  /// submit. [latex] is the raw expression built by the math keyboard.
  static String? validate(String latex) {
    final trimmed = latex.trim();
    if (trimmed.isEmpty) {
      return emptyMessage;
    }
    if (!hasContent(trimmed)) {
      return noContentMessage;
    }
    if (!isBalanced(trimmed)) {
      return unbalancedMessage;
    }
    return null;
  }

  /// [validate] plus the structured editor's own rule: every box that was
  /// opened must be filled. [hasEmptySlot] comes from the expression tree, so
  /// it catches boxes the LaTeX alone can't distinguish from empty groups.
  static String? validateExpression(
    String latex, {
    required bool hasEmptySlot,
  }) {
    if (latex.trim().isEmpty) return emptyMessage;
    if (hasEmptySlot) return emptyBoxMessage;
    return validate(latex);
  }

  /// Whether every `(`, `[` and `{` is matched by the right closer in order.
  static bool isBalanced(String s) {
    const openers = {'(': ')', '[': ']', '{': '}'};
    const closers = {')': '(', ']': '[', '}': '{'};
    final stack = <String>[];
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (openers.containsKey(ch)) {
        stack.add(ch);
      } else if (closers.containsKey(ch)) {
        if (stack.isEmpty || stack.removeLast() != closers[ch]) return false;
      }
    }
    return stack.isEmpty;
  }

  /// True once there's at least one digit or letter — i.e. some actual maths,
  /// not just operators or brackets.
  static bool hasContent(String s) => RegExp(r'[0-9A-Za-z]').hasMatch(s);
}
