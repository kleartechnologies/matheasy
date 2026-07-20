import 'package:flutter/material.dart';

import '../../../../core/animations/floaty.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';

/// One faint math glyph drifting in the onboarding backdrop.
///
/// [align] places it proportionally (x/y in −1..1); [accent] tints it emerald
/// instead of the neutral muted ink so a page can echo the brand colour.
@immutable
class OnboardingGlyph {
  const OnboardingGlyph(
    this.symbol,
    this.align, {
    this.size = 30,
    this.opacity = 0.9,
    this.accent = false,
  });

  final String symbol;
  final Alignment align;
  final double size;

  /// Multiplier applied on top of the base faint alpha (keep glyphs decorative).
  final double opacity;
  final bool accent;
}

/// A decorative, non-interactive layer of drifting math symbols behind an
/// onboarding page — the ambient "π √ ∑ ∫ ∞" motif from the design.
///
/// Each glyph bobs gently via [Floaty] and freezes flat under reduced motion.
/// Purely presentational: it never intercepts touches.
class OnboardingBackdrop extends StatelessWidget {
  const OnboardingBackdrop({super.key, required this.glyphs});

  final List<OnboardingGlyph> glyphs;

  // Slightly different periods so the glyphs never bob in lockstep.
  static const List<Duration> _periods = [
    Duration(milliseconds: 5200),
    Duration(milliseconds: 6100),
    Duration(milliseconds: 4600),
    Duration(milliseconds: 6800),
    Duration(milliseconds: 5600),
  ];

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final colors = context.colors;
    final accentColor = context.isDark
        ? AppColors.primaryLight
        : AppColors.primary;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Stack(
          children: [
            for (var i = 0; i < glyphs.length; i++)
              Align(
                alignment: glyphs[i].align,
                child: Floaty(
                  enabled: !reduced,
                  amplitude: 5,
                  period: _periods[i % _periods.length],
                  child: Text(
                    glyphs[i].symbol,
                    style: TextStyle(
                      fontSize: glyphs[i].size,
                      fontWeight: FontWeight.w600,
                      color: (glyphs[i].accent ? accentColor : colors.textMuted)
                          .withValues(
                            alpha:
                                (glyphs[i].accent ? 0.16 : 0.12) *
                                glyphs[i].opacity,
                          ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
