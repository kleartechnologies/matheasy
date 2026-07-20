import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/localization/l10n_extension.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/onboarding_backdrop.dart';
import '../widgets/onboarding_layouts.dart';

/// Onboarding 1/5 — "Understand math, don't just copy answers." A scanner
/// viewfinder framing an equation with a sweeping scan line, and a solved chip.
class ScanIntroPage extends StatelessWidget {
  const ScanIntroPage({super.key});

  @override
  Widget build(BuildContext context) {
    return OnboardingHeroPage(
      glyphs: const [
        OnboardingGlyph('π', Alignment(0.84, -0.74)),
        OnboardingGlyph('√', Alignment(-0.86, 0.5), size: 34),
        OnboardingGlyph('∞', Alignment(0.72, 0.78), size: 28),
        OnboardingGlyph('Σ', Alignment(-0.78, -0.52), size: 26),
      ],
      illustration: const _ScannerCard(),
      headline: context.l10n.onboardingScanTitle,
      subtitle: context.l10n.onboardingScanSubtitle,
    );
  }
}

class _ScannerCard extends StatefulWidget {
  const _ScannerCard();

  @override
  State<_ScannerCard> createState() => _ScannerCardState();
}

class _ScannerCardState extends State<_ScannerCard>
    with SingleTickerProviderStateMixin {
  static const double _cardW = 300;
  static const double _cardH = 168;

  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    // Sweep down then back up, forever. Reduced motion is handled in build.
    _scan.repeat(reverse: true);
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (reduced && _scan.isAnimating) {
      _scan
        ..stop()
        ..value = 0.5;
    } else if (!reduced && !_scan.isAnimating) {
      _scan.repeat(reverse: true);
    }
    // Emerald that clears the 3:1 graphical floor on the card surface — the
    // identity emerald (primary) is 2.97:1 on white and is brand-art only.
    final frame = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryAction;

    return SizedBox(
      width: _cardW + 24,
      height: _cardH + 56,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Container(
            width: _cardW,
            height: _cardH,
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: AppRadius.lgRadius,
              boxShadow: context.elevation.card,
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ScanFramePainter(
                      frame: frame,
                      grid: colors.textMuted.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    '3x + 5 = 20',
                    style: AppTypography.headingMedium.copyWith(
                      color: colors.textPrimary,
                      fontStyle: FontStyle.italic,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _scan,
                  builder: (context, _) {
                    final t = Curves.easeInOut.transform(_scan.value);
                    return Positioned(
                      top: 18 + t * (_cardH - 36),
                      left: 14,
                      right: 14,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: frame,
                          borderRadius: AppRadius.pillRadius,
                          boxShadow: [
                            BoxShadow(
                              color: frame.withValues(alpha: 0.45),
                              blurRadius: 12,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const Positioned(right: 0, bottom: 0, child: _SolvedChip()),
        ],
      ),
    );
  }
}

/// Draws the faint measurement grid plus four emerald corner brackets — the
/// "scanner viewfinder" look.
class _ScanFramePainter extends CustomPainter {
  const _ScanFramePainter({required this.frame, required this.grid});

  final Color frame;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    const step = 26.0;
    for (var x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final bracket = Paint()
      ..color = frame
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const inset = 14.0;
    // Top-left
    _corner(canvas, bracket, const Offset(inset, inset), 1, 1);
    // Top-right
    _corner(canvas, bracket, Offset(size.width - inset, inset), -1, 1);
    // Bottom-left
    _corner(canvas, bracket, Offset(inset, size.height - inset), 1, -1);
    // Bottom-right
    _corner(
      canvas,
      bracket,
      Offset(size.width - inset, size.height - inset),
      -1,
      -1,
    );
  }

  void _corner(Canvas canvas, Paint p, Offset o, double dx, double dy) {
    const len = 20.0;
    canvas.drawLine(o, o.translate(len * dx, 0), p);
    canvas.drawLine(o, o.translate(0, len * dy), p);
  }

  @override
  bool shouldRepaint(_ScanFramePainter old) =>
      old.frame != frame || old.grid != grid;
}

class _SolvedChip extends StatelessWidget {
  const _SolvedChip();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = context.isDark
        ? AppColors.primaryLight
        : AppColors.primaryAction;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdRadius,
        boxShadow: context.elevation.raised,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 17, color: accent),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.l10n.onboardingSolvedLabel.toUpperCase(),
                style: AppTypography.label.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'x = 5',
                style: AppTypography.title.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
