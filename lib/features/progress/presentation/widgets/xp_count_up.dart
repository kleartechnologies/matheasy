import 'package:flutter/material.dart';

import '../../../../core/theme/app_durations.dart';

/// Animates an integer counting up to [value] on first build — for XP totals and
/// reward reveals.
class XpCountUp extends StatelessWidget {
  const XpCountUp({
    super.key,
    required this.value,
    required this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = AppDurations.slow,
  });

  final int value;
  final TextStyle style;
  final String prefix;
  final String suffix;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: duration,
      curve: AppCurves.standard,
      builder: (context, current, _) => Text(
        '$prefix$current$suffix',
        style: style,
      ),
    );
  }
}
