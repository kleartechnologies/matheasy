import 'package:flutter/widgets.dart';

import '../extensions/context_extensions.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'matheasy_mark.dart';

/// Which pieces of the logo to render.
enum MatheasyLogoVariant {
  /// The symbol only (the M mark).
  mark,

  /// The "Matheasy" wordmark only.
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
/// (the M) and the Manrope wordmark.
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
/// const MatheasyLogo(wordmarkAccent: true);               // two-tone "Math·easy"
/// ```
class MatheasyLogo extends StatelessWidget {
  const MatheasyLogo({
    super.key,
    this.variant = MatheasyLogoVariant.horizontal,
    this.size = MatheasyLogoSize.medium,
    this.markSize,
    this.markColor,
    this.wordmarkColor,
    this.wordmarkAccent = false,
    this.onDark,
  });

  final MatheasyLogoVariant variant;
  final MatheasyLogoSize size;

  /// Explicit mark edge length. When set it overrides [size].
  final double? markSize;

  /// Mark color override. Defaults to brand Emerald.
  final Color? markColor;

  /// Wordmark color override. Defaults to brand ink (or white when [onDark]).
  final Color? wordmarkColor;

  /// When true, the "easy" half of the wordmark is drawn in the brand accent
  /// (Emerald on light, Mint on dark) — the featured two-tone lockup.
  final bool wordmarkAccent;

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
    // The accent tints the "easy" half — that is wordmark TEXT, so it takes the
    // legible-as-label emerald (primaryDark on light, 6.83:1), never the 2.97:1
    // identity tone. The mark beside it still uses full [AppColors.primary]:
    // there it is brand art, not text.
    final accent = wordmarkAccent
        ? (dark ? AppColors.primaryLight : AppColors.primaryDark)
        : null;
    final dim = _markDimension;

    switch (variant) {
      case MatheasyLogoVariant.mark:
        return MatheasyMark(size: dim, color: mark, semanticLabel: 'Matheasy');
      case MatheasyLogoVariant.wordmark:
        return _Wordmark(fontSize: dim * 0.86, color: word, accentColor: accent);
      case MatheasyLogoVariant.horizontal:
        return Semantics(
          label: 'Matheasy',
          image: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MatheasyMark(size: dim, color: mark),
              SizedBox(width: dim * 0.16),
              _Wordmark(fontSize: dim * 0.86, color: word, accentColor: accent),
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
              SizedBox(height: dim * 0.22),
              _Wordmark(fontSize: dim * 0.68, color: word, accentColor: accent),
            ],
          ),
        );
    }
  }
}

/// The "Matheasy" wordmark: one word, capital M, Manrope ExtraBold, −3.5%
/// tracking, per the brand system. When [accentColor] is set, the "easy" half
/// is drawn in the brand accent (the featured two-tone lockup); otherwise it is
/// a single solid run so it can't drift from the mark.
class _Wordmark extends StatelessWidget {
  const _Wordmark({
    required this.fontSize,
    required this.color,
    this.accentColor,
  });

  final double fontSize;
  final Color color;
  final Color? accentColor;

  static const _behavior = TextHeightBehavior(
    applyHeightToFirstAscent: false,
    applyHeightToLastDescent: false,
  );

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.displayLarge.copyWith(
      fontSize: fontSize,
      color: color,
      letterSpacing: -fontSize * 0.035, // brand tracking: −3.5%
      height: 1,
    );
    if (accentColor == null) {
      return Text('Matheasy', style: style, textHeightBehavior: _behavior);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Math'),
          TextSpan(text: 'easy', style: TextStyle(color: accentColor)),
        ],
      ),
      textHeightBehavior: _behavior,
    );
  }
}
