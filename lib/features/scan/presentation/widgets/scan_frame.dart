import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_durations.dart';

/// The scanning frame: four rounded corner guides plus a sweeping scan line.
///
/// The guides use the Matheasy primary accent (emerald) — never Photomath's red
/// (spec §2). When [locked] (a candidate is detected) they brighten and the scan
/// line stops.
class ScanFrame extends StatefulWidget {
  const ScanFrame({super.key, required this.locked});

  final bool locked;

  @override
  State<ScanFrame> createState() => _ScanFrameState();
}

class _ScanFrameState extends State<ScanFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.sparkle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.locked ? AppColors.primaryLight : AppColors.primary;
    // Respect reduced-motion: drop the sweeping scan line, keep the guides.
    final animate = !widget.locked && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            _corner(Alignment.topLeft, color),
            _corner(Alignment.topRight, color),
            _corner(Alignment.bottomLeft, color),
            _corner(Alignment.bottomRight, color),
            if (animate)
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_controller.value);
                  return Positioned(
                    top: 6 + t * (constraints.maxHeight - 12),
                    left: 10,
                    right: 10,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0x0034D399),
                            AppColors.primaryTint,
                            Color(0x0034D399),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primaryTint.withValues(alpha: 0.7),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _corner(Alignment alignment, Color color) {
    final isTop = alignment.y < 0;
    final isLeft = alignment.x < 0;
    return Align(
      alignment: alignment,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          border: Border(
            top: isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
            bottom:
                !isTop ? BorderSide(color: color, width: 3) : BorderSide.none,
            left: isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
            right:
                !isLeft ? BorderSide(color: color, width: 3) : BorderSide.none,
          ),
          borderRadius: BorderRadius.only(
            topLeft: isTop && isLeft ? const Radius.circular(14) : Radius.zero,
            topRight: isTop && !isLeft ? const Radius.circular(14) : Radius.zero,
            bottomLeft:
                !isTop && isLeft ? const Radius.circular(14) : Radius.zero,
            bottomRight:
                !isTop && !isLeft ? const Radius.circular(14) : Radius.zero,
          ),
        ),
      ),
    );
  }
}
