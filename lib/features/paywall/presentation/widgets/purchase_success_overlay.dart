import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:matheasy/core/brand/brand.dart';

import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// The Matheasy Pro celebration — shown the moment a purchase succeeds, before
/// the paywall dismisses.
///
/// Design brief: *Duolingo delight + Apple elegance.* The brand mark springs in
/// on a real [SpringSimulation] (one soft overshoot), the headline and subtitle
/// rise, and the three unlocked-Pro perks check off one-by-one — all over a calm
/// field of math symbols (π √ ∑ ∫ ∞ …) drifting upward. The confetti is
/// deliberately restrained: low-alpha emerald / gold / white only, no bursts, no
/// fireworks, no loud colour. Every motion honours reduced-motion (it snaps to
/// the finished state), and the whole sequence is driven by two controllers so
/// it stays cheap.
class PurchaseSuccessOverlay extends StatefulWidget {
  const PurchaseSuccessOverlay({super.key, required this.planName});

  final String planName;

  /// The celebration window — the paywall dismisses when this elapses, so the
  /// [_master] timeline is sized to match (entrance ≈ first 1.6s, then the
  /// confetti drifts through the hold).
  static const Duration duration = Duration(milliseconds: 2800);

  @override
  State<PurchaseSuccessOverlay> createState() => _PurchaseSuccessOverlayState();
}

class _PurchaseSuccessOverlayState extends State<PurchaseSuccessOverlay>
    with TickerProviderStateMixin {
  // A single linear timeline drives the backdrop fade, the staggered text and
  // the check-offs (via intervals) and the confetti progress.
  late final AnimationController _master = AnimationController(
    vsync: this,
    duration: PurchaseSuccessOverlay.duration,
  );

  // The logo rides a physical spring (unbounded so it can overshoot past 1).
  late final AnimationController _logo = AnimationController.unbounded(
    vsync: this,
  );

  // Under-damped a touch (ζ ≈ 0.6) → a single, gentle overshoot, then settle.
  static const SpringDescription _spring = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 16,
  );

  late final List<_Particle> _particles = _Particle.field(count: 20);

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Honour reduced-motion: show the finished celebration immediately, no
    // drifting confetti, no spring — the reward still lands, just calmly.
    if (MediaQuery.disableAnimationsOf(context)) {
      _master.value = 1;
      _logo.value = 1;
    } else {
      _master.forward();
      _logo.animateWith(SpringSimulation(_spring, 0, 1, 0));
    }
  }

  @override
  void dispose() {
    for (final p in _particles) {
      p.disposeGlyph();
    }
    _master.dispose();
    _logo.dispose();
    super.dispose();
  }

  /// Clamped 0→1 progress of a sub-interval of the master timeline.
  double _seg(double begin, double end) =>
      ((_master.value - begin) / (end - begin)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final perks = <String>[
      context.l10n.paywallSuccessPerkScans,
      context.l10n.paywallSuccessPerkVisual,
      context.l10n.paywallSuccessPerkPractice,
    ];

    return AnimatedBuilder(
      animation: Listenable.merge([_master, _logo]),
      builder: (context, _) {
        final backdrop = Curves.easeOut.transform(_seg(0, 0.09));
        return Opacity(
          opacity: backdrop,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: AppColors.premiumGradient,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Ambient math-symbol field, behind everything, decorative only.
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _ConfettiPainter(
                      particles: _particles,
                      t: _master.value,
                    ),
                  ),
                ),
                // Centred, but scrollable so the celebration can never overflow
                // on a small screen at large accessibility text sizes (the
                // content stays fully scalable — no text-size cap here).
                LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        label: context.l10n.paywallNowOnPlan(widget.planName),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.screenH),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLogo(),
                              const SizedBox(height: AppSpacing.xl),
                              _rise(
                                _seg(0.12, 0.30),
                                child: Text(
                                  context.l10n.paywallAllSet,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.displaySmall.copyWith(
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _rise(
                                _seg(0.18, 0.36),
                                child: Text(
                                  context.l10n.paywallWelcomeToPlan(
                                    widget.planName,
                                  ),
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyMedium.copyWith(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              for (final (i, label) in perks.indexed) ...[
                                if (i > 0)
                                  const SizedBox(height: AppSpacing.md),
                                _PerkRow(
                                  label: label,
                                  // Stagger the check-offs one-by-one.
                                  progress: _seg(
                                    0.34 + i * 0.10,
                                    0.50 + i * 0.10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogo() {
    // Fade in fast as it grows so a near-zero scale never reads as a stray dot.
    final scale = _logo.value;
    final opacity = (scale * 3).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.gold.withValues(alpha: 0.32),
                AppColors.gold.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: const MatheasyBrandAvatar(size: 120),
        ),
      ),
    );
  }

  /// Fade + a small upward rise for an entering element.
  Widget _rise(double t, {required Widget child}) {
    return Opacity(
      opacity: Curves.easeOut.transform(t),
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - Curves.easeOutCubic.transform(t))),
        child: child,
      ),
    );
  }
}

/// One check-off row: a gold check that pops in on [progress] beside its label.
class _PerkRow extends StatelessWidget {
  const _PerkRow({required this.label, required this.progress});

  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    // The check overshoots (easeOutBack); the row fades with a plain ease so the
    // text never wobbles.
    final pop = Curves.easeOutBack.transform(progress.clamp(0.0, 1.0));
    final fade = Curves.easeOut.transform(progress);
    return Opacity(
      opacity: fade,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.scale(
            scale: pop.clamp(0.0, 1.2),
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.goldGradient,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 17,
                color: AppColors.onGold,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single drifting math symbol. All of its "randomness" is drawn from a fixed
/// seed so the field is deterministic (stable in tests, reproducible on screen)
/// while still reading as scattered.
class _Particle {
  _Particle({
    required this.symbol,
    required this.xFraction,
    required this.size,
    required this.color,
    required this.baseAlpha,
    required this.phase,
    required this.swayAmplitude,
    required this.swayFrequency,
    required this.rotationTurns,
    required this.riseCycles,
  });

  final String symbol;
  final double xFraction;
  final double size;
  final Color color;
  final double baseAlpha;
  final double phase;
  final double swayAmplitude;
  final double swayFrequency;
  final double rotationTurns; // signed → random spin direction
  final double riseCycles;

  // The glyph geometry (symbol + size + weight) never changes — only the
  // per-frame opacity does — so shape + lay it out ONCE and reuse it every
  // frame, instead of allocating a fresh TextPainter per particle per frame.
  TextPainter? _glyph;
  TextPainter get glyph => _glyph ??= (TextPainter(
    text: TextSpan(
      text: symbol,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color, // full alpha; the envelope opacity is applied at paint
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout());

  void disposeGlyph() {
    _glyph?.dispose();
    _glyph = null;
  }

  static const List<String> symbols = [
    'π',
    '√',
    '∑',
    '∫',
    '∞',
    'x²',
    'θ',
    'Δ',
    'f(x)',
  ];

  static List<Color> get _palette => const [
    AppColors.primaryLight, // emerald
    AppColors.goldLight, // gold
    AppColors.white, // white
  ];

  static List<_Particle> field({required int count}) {
    final rnd = math.Random(7);
    double lerp(double a, double b) => a + (b - a) * rnd.nextDouble();
    return List.generate(count, (i) {
      return _Particle(
        symbol: symbols[i % symbols.length],
        xFraction: rnd.nextDouble(),
        size: lerp(15, 30),
        color: _palette[rnd.nextInt(_palette.length)],
        baseAlpha: lerp(0.10, 0.26),
        phase: rnd.nextDouble(),
        swayAmplitude: lerp(6, 20),
        swayFrequency: lerp(0.5, 1.5),
        rotationTurns: lerp(0.3, 1.2) * (rnd.nextBool() ? 1 : -1),
        riseCycles: lerp(1.1, 1.7),
      );
    });
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.particles, required this.t});

  final List<_Particle> particles;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      // Looping upward progress; sin() envelope means the symbol is invisible at
      // both ends, so the wrap from top back to bottom is seamless.
      final prog = (p.phase + t * p.riseCycles) % 1.0;
      final envelope = math.sin(math.pi * prog);
      if (envelope <= 0.02) continue;

      final dx =
          size.width * p.xFraction +
          p.swayAmplitude *
              math.sin(
                2 * math.pi * p.swayFrequency * prog + p.phase * 2 * math.pi,
              );
      // Rises from just below the bottom to just above the top.
      final dy = size.height * (1.06 - 1.22 * prog);

      final tp = p.glyph; // laid out once, reused
      final alpha = (p.baseAlpha * envelope).clamp(0.0, 1.0);

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rotationTurns * prog * 2 * math.pi);
      // Apply the per-frame fade as a group opacity over the cached glyph — no
      // re-shaping, no per-frame allocation. The layer bounds are the glyph's
      // own (small) rect in this rotated local space.
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: tp.width,
          height: tp.height,
        ),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore(); // saveLayer
      canvas.restore(); // save
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
