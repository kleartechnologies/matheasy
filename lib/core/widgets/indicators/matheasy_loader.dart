import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../extensions/context_extensions.dart';
import '../../theme/app_colors.dart';

/// A calm, on-brand loading animation: three emerald dots pulsing in a
/// staggered wave.
///
/// It speaks the app's existing "thinking" motion language (the chat typing
/// indicator) but is tuned for full loading moments — smooth sine easing, brand
/// colour, size-configurable — so a loading screen reads as *working*, not as a
/// static logo. Honours reduced-motion (the dots hold still at a calm opacity).
///
/// Purely decorative: it carries no semantics, so the surrounding loading
/// message owns the screen-reader announcement.
class MatheasyLoader extends StatefulWidget {
  const MatheasyLoader({super.key, this.color, this.dotSize = 9, this.gap = 6});

  /// Dot colour. Defaults to the emerald that reads on the current surface —
  /// [AppColors.primaryLight] on dark, [AppColors.primaryDark] on light.
  final Color? color;

  /// Diameter of each dot.
  final double dotSize;

  /// Horizontal space between dots.
  final double gap;

  @override
  State<MatheasyLoader> createState() => _MatheasyLoaderState();
}

class _MatheasyLoaderState extends State<MatheasyLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour reduced-motion (mirrors Floaty): hold the dots still rather than
    // looping the wave.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }

    final color =
        widget.color ??
        (context.isDark ? AppColors.primaryLight : AppColors.primaryDark);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (i) => _Dot(
          controller: _controller,
          index: i,
          color: color,
          size: widget.dotSize,
          gap: widget.gap,
          reduceMotion: reduceMotion,
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.controller,
    required this.index,
    required this.color,
    required this.size,
    required this.gap,
    required this.reduceMotion,
  });

  final AnimationController controller;
  final int index;
  final Color color;
  final double size;
  final double gap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
    final padding = EdgeInsets.symmetric(horizontal: gap / 2);

    if (reduceMotion) {
      return Padding(
        padding: padding,
        child: Opacity(opacity: 0.7, child: dot),
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Smooth raised-cosine bump (0→1→0, peak at phase 0), each dot lagging
        // the previous by a fifth of the cycle → a gentle travelling wave.
        final phase = (controller.value - index * 0.2) % 1.0;
        final bump = 0.5 + 0.5 * math.cos(2 * math.pi * phase);
        return Padding(
          padding: padding,
          child: Opacity(
            opacity: 0.4 + 0.6 * bump,
            child: Transform.scale(scale: 0.7 + 0.3 * bump, child: child),
          ),
        );
      },
      child: dot,
    );
  }
}
