import 'package:flutter/widgets.dart';

import '../services/haptics_service.dart';
import '../theme/app_durations.dart';

/// Wraps any tappable surface with the app's signature "press to scale-down"
/// feedback and optional haptic tick. Buttons and cards compose this so the
/// interaction language stays consistent everywhere.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.haptic = true,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final bool haptic;
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null;

  void _setDown(bool value) {
    if (!_enabled) return;
    if (_down != value) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setDown(true),
      onTapUp: (_) => _setDown(false),
      onTapCancel: () => _setDown(false),
      onTap: _enabled
          ? () {
              if (widget.haptic) HapticsService.selection();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: AppDurations.press,
        curve: AppCurves.standard,
        child: widget.child,
      ),
    );
  }
}
