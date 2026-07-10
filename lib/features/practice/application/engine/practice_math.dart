import 'dart:math' as math;

/// Small, dependency-free math helpers shared by the template + rule-based
/// generators. Kept pure so they're trivially unit-testable.
class PracticeMath {
  const PracticeMath._();

  /// Greatest common divisor of |a| and |b| (gcd(0, 0) == 1 to avoid /0).
  static int gcd(int a, int b) {
    a = a.abs();
    b = b.abs();
    while (b != 0) {
      final t = b;
      b = a % b;
      a = t;
    }
    return a == 0 ? 1 : a;
  }

  /// Lowest common multiple of |a| and |b|.
  static int lcm(int a, int b) => (a ~/ gcd(a, b)) * b.abs();

  /// A fraction reduced to lowest terms, with the sign carried on the
  /// numerator. Returns `(numerator, denominator)`.
  static (int, int) simplifyFraction(int numerator, int denominator) {
    if (denominator == 0) return (numerator, 1);
    final sign = denominator < 0 ? -1 : 1;
    final n = numerator * sign;
    final d = denominator * sign;
    final g = gcd(n, d);
    return (n ~/ g, d ~/ g);
  }

  /// Formats a fraction as a plain string in lowest terms — an integer when the
  /// denominator reduces to 1 (e.g. `4/2` → `2`, `6/8` → `3/4`).
  static String formatFraction(int numerator, int denominator) {
    final (n, d) = simplifyFraction(numerator, denominator);
    if (d == 1) return '$n';
    return '$n/$d';
  }

  /// Formats a fraction as LaTeX (`\frac{n}{d}`), or the integer when it
  /// reduces (negatives keep the sign outside the fraction).
  static String fractionLatex(int numerator, int denominator) {
    final (n, d) = simplifyFraction(numerator, denominator);
    if (d == 1) return '$n';
    if (n < 0) return r'-\frac{' '${n.abs()}' '}{' '$d' '}';
    return r'\frac{' '$n' '}{' '$d' '}';
  }

  /// Whether [value] is a perfect square.
  static bool isPerfectSquare(int value) {
    if (value < 0) return false;
    final root = math.sqrt(value).round();
    return root * root == value;
  }
}
