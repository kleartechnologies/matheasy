import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';

/// Circular progress indicator with an optional child in the middle (e.g. the
/// completion percentage). Painted so the stroke uses the brand gradient.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 72,
    this.strokeWidth = 8,
    this.child,
    this.trackColor,
    this.progressColor = AppColors.primary,
  }) : assert(value >= 0 && value <= 1, 'value must be between 0 and 1');

  final double value;
  final double size;
  final double strokeWidth;
  final Widget? child;
  final Color? trackColor;
  final Color progressColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0.0, 1.0),
          strokeWidth: strokeWidth,
          trackColor: trackColor ?? context.colors.surfaceMuted,
          progressColor: progressColor,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.value,
    required this.strokeWidth,
    required this.trackColor,
    required this.progressColor,
  });

  final double value;
  final double strokeWidth;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.width - strokeWidth) / 2;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    final progress = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
        colors: [progressColor, progressColor.withValues(alpha: 0.7)],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.progressColor != progressColor ||
      oldDelegate.trackColor != trackColor;
}
