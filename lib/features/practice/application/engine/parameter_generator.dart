import 'dart:math';

/// A thin, seedable wrapper over [Random] giving the generators readable,
/// intention-revealing draws (`between`, `nonZeroBetween`, `pick`, `chance`).
///
/// Seeding the underlying [Random] makes the whole engine deterministic, which
/// is how the tests assert on generated content and anti-repetition.
class ParameterGenerator {
  ParameterGenerator([Random? random]) : _random = random ?? Random();

  final Random _random;

  /// An integer in the inclusive range [min, max]. If [max] < [min] the range
  /// is treated as a single value ([min]) rather than throwing.
  int between(int min, int max) {
    if (max <= min) return min;
    return min + _random.nextInt(max - min + 1);
  }

  /// Like [between] but never returns 0 (useful for coefficients / offsets).
  int nonZeroBetween(int min, int max) {
    if (min == 0 && max == 0) return 1;
    var value = between(min, max);
    var guard = 0;
    while (value == 0 && guard < 8) {
      value = between(min, max);
      guard++;
    }
    return value == 0 ? (max > 0 ? 1 : -1) : value;
  }

  /// A uniformly random element of [items] (must be non-empty).
  T pick<T>(List<T> items) => items[_random.nextInt(items.length)];

  /// True with probability [p] (default 0.5).
  bool chance([double p = 0.5]) => _random.nextDouble() < p;

  /// A shuffled copy of [items] (leaves the original untouched).
  List<T> shuffled<T>(List<T> items) {
    final copy = [...items];
    copy.shuffle(_random);
    return copy;
  }

  /// Either +1 or -1.
  int sign() => _random.nextBool() ? 1 : -1;
}
