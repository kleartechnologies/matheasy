import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_durations.dart';

/// A restrained, on-brand "math confetti" burst for a moment of delight (the
/// Animated Learning Engine's final-answer beat). A small deterministic field of
/// low-alpha math glyphs (π √ ∑ ∫ ∞ x θ) drifts upward with rotation and a gentle
/// rise-and-fade envelope — premium, never carnival. Plays ONCE each time
/// [active] flips true; renders nothing under Reduce Motion.
class MathCelebration extends StatefulWidget {
  const MathCelebration({super.key, required this.active, this.glyphColor});

  /// Flip to `true` to trigger a single burst.
  final bool active;

  /// Overrides the emerald default (e.g. the current step's accent).
  final Color? glyphColor;

  @override
  State<MathCelebration> createState() => _MathCelebrationState();
}

class _MathCelebrationState extends State<MathCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppDurations.celebrate,
  );

  static const _glyphs = ['π', '√', '∑', '∫', '∞', 'x', 'θ', '+', '=', '%'];
  late final List<_Particle> _field = _build();

  List<_Particle> _build() {
    final rng = math.Random(7); // fixed seed → identical, tasteful field
    return List.generate(18, (i) {
      return _Particle(
        x: rng.nextDouble(),
        glyph: _glyphs[i % _glyphs.length],
        size: 12 + rng.nextDouble() * 12,
        rise: 0.55 + rng.nextDouble() * 0.4,
        drift: (rng.nextDouble() - 0.5) * 0.25,
        spin: (rng.nextDouble() - 0.5) * 2,
        delay: rng.nextDouble() * 0.25,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The widget is only mounted when already active (the player inserts it
    // inside `if (step.isAnswer)`), so didUpdateWidget's false→true transition
    // never fires — kick the burst off on first mount here instead.
    if (widget.active &&
        _c.status == AnimationStatus.dismissed &&
        !MediaQuery.disableAnimationsOf(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(MathCelebration old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _c.forward(from: 0);
    } else if (!widget.active && old.active) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();
    final color = widget.glyphColor ?? AppColors.primary;
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            if (_c.value == 0 && !_c.isAnimating) {
              return const SizedBox.expand();
            }
            return CustomPaint(
              size: Size.infinite,
              painter: _ConfettiPainter(
                t: _c.value,
                field: _field,
                color: color,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.x,
    required this.glyph,
    required this.size,
    required this.rise,
    required this.drift,
    required this.spin,
    required this.delay,
  });

  final double x; // 0..1 horizontal start
  final String glyph;
  final double size;
  final double rise; // fraction of height travelled
  final double drift; // horizontal drift
  final double spin; // radians of rotation over the burst
  final double delay; // 0..0.25 stagger
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.t, required this.field, required this.color});

  final double t;
  final List<_Particle> field;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in field) {
      final local = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      // Rise from just below-centre, easing out; fade in then out (sin envelope).
      final y = size.height * (0.72 - p.rise * local);
      final x = size.width * (p.x + p.drift * local);
      final envelope = math.sin(math.pi * local);
      final alpha = (envelope * 0.5).clamp(0.0, 0.5);
      if (alpha <= 0.01) continue;

      final tp = TextPainter(
        text: TextSpan(
          text: p.glyph,
          style: TextStyle(
            fontSize: p.size,
            fontWeight: FontWeight.w700,
            color: color.withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * local);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.t != t || old.color != color;
}
