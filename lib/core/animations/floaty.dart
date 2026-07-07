import 'package:flutter/widgets.dart';

import '../theme/app_durations.dart';

/// Ambient vertical bob used for the Numi mascot and floating accents.
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
  void initState() {
    super.initState();
    if (widget.enabled) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant Floaty oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.enabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
