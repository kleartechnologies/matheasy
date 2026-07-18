import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/app_durations.dart';

/// Reusable animation primitives built on the motion tokens
/// ([AppDurations] / [AppCurves]). No screen should hardcode a duration or
/// curve — compose these instead. Pass a [delay] to stagger a list of children.
class AppTransitions {
  const AppTransitions._();

  /// Fade a child in on first build.
  static Widget fadeIn({
    required Widget child,
    Duration duration = AppDurations.medium,
    Duration delay = Duration.zero,
    Curve curve = AppCurves.standard,
  }) {
    return _EntranceAnimator(
      duration: duration,
      delay: delay,
      curve: curve,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }

  /// Scale + fade a child in ("pop" entrance).
  static Widget scaleIn({
    required Widget child,
    Duration duration = AppDurations.medium,
    Duration delay = Duration.zero,
    Curve curve = AppCurves.emphasized,
    double from = 0.9,
  }) {
    return _EntranceAnimator(
      duration: duration,
      delay: delay,
      curve: curve,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: from + (1 - from) * t, child: child),
      ),
      child: child,
    );
  }

  /// Slide up + fade a child in ("rise" entrance).
  static Widget slideUp({
    required Widget child,
    Duration duration = AppDurations.medium,
    Duration delay = Duration.zero,
    Curve curve = AppCurves.standard,
    double offset = 16,
  }) {
    return _EntranceAnimator(
      duration: duration,
      delay: delay,
      curve: curve,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, offset * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  /// A [SwitchTransition]-friendly fade-through builder for `AnimatedSwitcher`.
  static Widget fadeThrough(Widget child, Animation<double> animation) {
    return FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1).animate(animation),
        child: child,
      ),
    );
  }
}

/// Drives a one-shot entrance animation from 0→1 on mount, after an optional
/// [delay] (used to stagger lists).
class _EntranceAnimator extends StatefulWidget {
  const _EntranceAnimator({
    required this.duration,
    required this.delay,
    required this.curve,
    required this.builder,
    required this.child,
  });

  final Duration duration;
  final Duration delay;
  final Curve curve;
  final ValueWidgetBuilder<double> builder;
  final Widget child;

  @override
  State<_EntranceAnimator> createState() => _EntranceAnimatorState();
}

class _EntranceAnimatorState extends State<_EntranceAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final Animation<double> _animation =
      CurvedAnimation(parent: _controller, curve: widget.curve);
  Timer? _delayTimer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Honour reduced-motion (accessibility setting or OS), exactly as [Floaty]
    // does: skip the entrance tween and show the final state immediately, so a
    // staggered reveal never becomes a barrier to users who opted out of motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) =>
          widget.builder(context, _animation.value, child),
      child: widget.child,
    );
  }
}
