/// Validation for a typed math problem (manual entry) before it is handed to
/// the same recognize → solve pipeline a scanned problem uses.
///
/// Deliberately lenient: it only blocks input that would clearly waste a solve
/// (empty, unbalanced brackets, no actual math). The solver / AI tutor handle
/// everything else, exactly as they do for a scanned equation.
class MathInput {
  const MathInput._();

  /// Returns a short, user-facing error, or `null` when the input is good to
  /// submit. [latex] is the raw expression built by the math keyboard.
  static String? validate(String latex) {
    final trimmed = latex.trim();
    if (trimmed.isEmpty) {
      return 'Type a problem to solve.';
    }
    if (!hasContent(trimmed)) {
      return 'Add some numbers or variables.';
    }
    if (!isBalanced(trimmed)) {
      return "Check your brackets — something isn't closed.";
    }
    return null;
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
