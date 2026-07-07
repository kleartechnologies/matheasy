import 'package:flutter/widgets.dart';

/// Small, token-friendly widget helpers. These intentionally do NOT accept raw
/// padding numbers — callers pass spacing tokens from `AppSpacing`.
extension WidgetX on Widget {
  /// Wraps the widget in uniform [Padding].
  Widget paddedAll(double value) =>
      Padding(padding: EdgeInsets.all(value), child: this);

  /// Wraps the widget in symmetric [Padding].
  Widget paddedSymmetric({double h = 0, double v = 0}) => Padding(
        padding: EdgeInsets.symmetric(horizontal: h, vertical: v),
        child: this,
      );

  /// Makes the widget expand within a [Flex] (Row/Column).
  Widget expanded([int flex = 1]) => Expanded(flex: flex, child: this);
}
