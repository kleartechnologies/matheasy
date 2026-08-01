import 'package:flutter/widgets.dart';

/// An [AnimatedSize] that steps out of the way when motion is off.
///
/// Passing `Duration.zero` straight to [AnimatedSize] looks harmless and is
/// not: `RenderAnimatedSize` starts its controller from inside `performLayout`,
/// a zero-duration `forward()` completes synchronously, and the completion
/// listener calls `markNeedsLayout` on the render object still being laid out —
/// "A RenderAnimatedSize was mutated in its own performLayout implementation".
/// Every learner with Reduce Motion enabled hits it.
///
/// Reduced motion means *no* size animation, so the honest answer is to drop
/// the wrapper rather than animate for zero milliseconds. Use this anywhere the
/// duration is derived from `MediaQuery.disableAnimationsOf`.
class MotionAwareSize extends StatelessWidget {
  const MotionAwareSize({
    super.key,
    required this.duration,
    required this.child,
    this.curve = Curves.linear,
    this.alignment = Alignment.center,
  });

  /// How long the size change takes. [Duration.zero] means "don't animate".
  final Duration duration;

  final Curve curve;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}
