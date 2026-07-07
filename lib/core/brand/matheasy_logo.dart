import 'package:flutter/widgets.dart';

import '../extensions/context_extensions.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'matheasy_mark.dart';

/// Which pieces of the logo to render.
enum MatheasyLogoVariant {
  /// The symbol only (radical + equals mark).
  mark,

  /// The "matheasy" wordmark only.
  wordmark,

  /// Mark to the left of the wordmark (default).
  horizontal,

  /// Mark stacked above the wordmark.
  vertical,
}

/// Preset logo sizes. [MatheasyLogoSize.custom] is implied when [MatheasyLogo]
/// is given an explicit `markSize`.
enum MatheasyLogoSize { small, medium, large }

/// The official Matheasy logo — a reusable lockup of the brand [MatheasyMark]
/// (Concept A) and the Manrope wordmark.
///
/// One widget covers every configuration the brand system defines:
/// mark-only, wordmark-only, horizontal and vertical lockups, at small / medium
/// / large sizes, tuned for both light and dark surfaces.
///
/// ```dart
/// const MatheasyLogo();                                   // horizontal, medium
/// const MatheasyLogo(variant: MatheasyLogoVariant.vertical);
/// const MatheasyLogo(variant: MatheasyLogoVariant.mark, size: MatheasyLogoSize.large);
/// MatheasyLogo(onDark: true);                             // white-on-dark lockup
/// ```
class MatheasyLogo extends StatelessWidget {
  const MatheasyLogo({
    super.key,
    this.variant = MatheasyLogoVariant.horizontal,
    this.size = MatheasyLogoSize.medium,
    this.markSize,
    this.markColor,
    this.wordmarkColor,
    this.onDark,
  });

  final MatheasyLogoVariant variant;
  final MatheasyLogoSize size;

  /// Explicit mark edge length. When set it overrides [size].
  final double? markSize;

  /// Mark color override. Defaults to Brand Blue.
  final Color? markColor;

  /// Wordmark color override. Defaults to brand ink (or white when [onDark]).
  final Color? wordmarkColor;

  /// Force the dark-surface treatment (white wordmark). When null it is derived
  /// from the ambient theme brightness.
  final bool? onDark;

  double get _markDimension {
    if (markSize != null) return markSize!;
    switch (size) {
      case MatheasyLogoSize.small:
        return 24;
      case MatheasyLogoSize.medium:
        return 40;
      case MatheasyLogoSize.large:
        return 64;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = onDark ?? context.isDark;
    final mark = markColor ?? AppColors.primary;
    final word = wordmarkColor ?? (dark ? AppColors.white : AppColors.ink);
    final dim = _markDimension;

    switch (variant) {
      case MatheasyLogoVariant.mark:
        return MatheasyMark(
          size: dim,
          color: mark,
          semanticLabel: 'Matheasy',
        );
      case MatheasyLogoVariant.wordmark:
        return _Wordmark(fontSize: dim * 0.86, color: word);
      case MatheasyLogoVariant.horizontal:
        return Semantics(
          label: 'Matheasy',
          image: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MatheasyMark(size: dim, color: mark),
              SizedBox(width: dim * 0.34),
              _Wordmark(fontSize: dim * 0.86, color: word),
            ],
          ),
        );
      case MatheasyLogoVariant.vertical:
        return Semantics(
          label: 'Matheasy',
          image: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MatheasyMark(size: dim, color: mark),
              SizedBox(height: dim * 0.30),
              _Wordmark(fontSize: dim * 0.68, color: word),
            ],
          ),
        );
    }
  }
}

/// The lowercase "matheasy" wordmark: Manrope ExtraBold, −4% tracking, per the
/// brand system. Rendered as a single text run so it can't drift from the mark.
class _Wordmark extends StatelessWidget {
  const _Wordmark({required this.fontSize, required this.color});

  final double fontSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'matheasy',
      style: AppTypography.displayLarge.copyWith(
        fontSize: fontSize,
        color: color,
        letterSpacing: -fontSize * 0.04, // brand tracking: −4%
        height: 1,
      ),
      textHeightBehavior: const TextHeightBehavior(
        applyHeightToFirstAscent: false,
        applyHeightToLastDescent: false,
      ),
    );
  }
}
