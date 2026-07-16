import 'package:flutter/material.dart';

import '../../brand/brand.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_durations.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A Matheasy assistant message: the brand avatar paired with a speech bubble.
/// Use this for assistant turns in chat, inline hints, and the "verify" note on
/// solutions.
class MatheasyBubble extends StatelessWidget {
  const MatheasyBubble({
    super.key,
    required this.text,
    this.avatarSize = 34,
  });

  final String text;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.screenWidth * 0.82),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            MatheasyBrandAvatar(size: avatarSize),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppRadius.lg),
                    topRight: Radius.circular(AppRadius.lg),
                    bottomLeft: Radius.circular(6),
                    bottomRight: Radius.circular(AppRadius.lg),
                  ),
                  boxShadow: context.elevation.card,
                ),
                child: Text(
                  text,
                  style: AppTypography.bodyMedium
                      .copyWith(color: context.colors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated "Matheasy is typing…" indicator (three pulsing dots in a bubble).
class MatheasyTypingIndicator extends StatefulWidget {
  const MatheasyTypingIndicator({super.key, this.avatarSize = 34});

  final double avatarSize;

  @override
  State<MatheasyTypingIndicator> createState() =>
      _MatheasyTypingIndicatorState();
}

class _MatheasyTypingIndicatorState extends State<MatheasyTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.typing,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          MatheasyBrandAvatar(size: widget.avatarSize),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(AppRadius.lg),
              ),
              boxShadow: context.elevation.card,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _Dot(_controller, i)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.controller, this.index);

  final AnimationController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Stagger each dot by a third of the cycle.
        final phase = (controller.value - index * 0.18) % 1.0;
        final lifted = phase < 0.3;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Transform.translate(
            offset: Offset(0, lifted ? -3 : 0),
            child: Opacity(
              opacity: lifted ? 1 : 0.35,
              child: child,
            ),
          ),
        );
      },
      child: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: context.colors.textMuted,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
