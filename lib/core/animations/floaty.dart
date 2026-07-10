import 'package:flutter/widgets.dart';

import '../theme/app_durations.dart';

/// Ambient vertical bob used for the Matheasy brand avatar and floating accents.
/// Loops forever with a gentle ease; amplitude and period are tokenized.
class Floaty extends StatefulWidget {
  const Floaty({
    super.key,
    required this.child,
    this.amplitude = 8,
    this.period = AppDurations.floaty,
    this.enabled = true,
  });

  final Widget child;
  final double amplitude;
  final Duration period;
  final bool enabled;

  @override
  State<Floaty> createState() => _FloatyState();
}

class _FloatyState extends State<Floaty>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour reduced-motion (accessibility setting or OS): hold the avatar still
    // rather than looping the bob.
    final active = widget.enabled && !MediaQuery.disableAnimationsOf(context);
    if (active && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!active && _controller.isAnimating) {
      _controller
        ..stop()
        ..value = 0;
    }

    final curved = CurvedAnimation(parent: _controller, curve: AppCurves.ambient);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -widget.amplitude * curved.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}
