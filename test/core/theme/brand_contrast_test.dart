import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_colors.dart';
import 'package:matheasy/core/theme/app_semantic_colors.dart';

/// WCAG 2.x relative luminance of an opaque sRGB color.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.x contrast ratio between two opaque colors. Order-independent.
double contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// AA thresholds.
const _aaText = 4.5; // normal-size text
const _aaLarge = 3.0; // large text (>=18pt, or >=14pt bold) and non-text UI

void expectContrast(
  Color fg,
  Color bg,
  double min, {
  required String because,
}) {
  final ratio = contrast(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(min),
    reason:
        '$because — got ${ratio.toStringAsFixed(2)}:1, need ${min.toStringAsFixed(1)}:1',
  );
}

void main() {
  // These four tones are measured directly off the logo artwork (k-means over
  // the PNG). They are the identity. If one of them changes, the app no longer
  // matches the logo it ships with — that is a deliberate act, not a refactor,
  // so it should fail here first.
  group('logo anchors are pixel-exact to the artwork', () {
    test('emerald500 is the logo tile', () {
      expect(AppColors.emerald500, const Color(0xFF06AC60));
    });
    test('emerald600 is the logo mid shadow', () {
      expect(AppColors.emerald600, const Color(0xFF058446));
    });
    test('emerald700 is the logo deep shadow', () {
      expect(AppColors.emerald700, const Color(0xFF046934));
    });
    test('emerald900 is the logo outline', () {
      expect(AppColors.emerald900, const Color(0xFF024221));
    });

    test('the ramp is one hue family — every step sits in hue 145..160', () {
      const ramp = <Color>[
        AppColors.emerald50,
        AppColors.emerald100,
        AppColors.emerald200,
        AppColors.emerald300,
        AppColors.emerald400,
        AppColors.emerald500,
        AppColors.emerald600,
        AppColors.emerald700,
        AppColors.emerald800,
        AppColors.emerald900,
      ];
      for (final c in ramp) {
        final hue = HSLColor.fromColor(c).hue;
        expect(
          hue,
          inInclusiveRange(145, 160),
          reason:
              'every emerald must belong to the logo hue family; '
              '${c.toARGB32().toRadixString(16)} is at hue ${hue.toStringAsFixed(0)}',
        );
      }
    });

    test('the ramp descends monotonically in luminance', () {
      const ramp = <Color>[
        AppColors.emerald50,
        AppColors.emerald100,
        AppColors.emerald200,
        AppColors.emerald300,
        AppColors.emerald400,
        AppColors.emerald500,
        AppColors.emerald600,
        AppColors.emerald700,
        AppColors.emerald800,
        AppColors.emerald900,
      ];
      for (var i = 1; i < ramp.length; i++) {
        expect(
          _luminance(ramp[i]),
          lessThan(_luminance(ramp[i - 1])),
          reason: 'ramp step $i must be darker than step ${i - 1}',
        );
      }
    });
  });

  // The identity/action split exists precisely because the logo's emerald is
  // 2.97:1 against white. These tests are the reason the split is not optional.
  group('the identity / action split holds', () {
    test('primary is the identity emerald and is NOT white-text safe', () {
      expect(AppColors.primary, AppColors.emerald500);
      // This is the whole point of primaryAction existing. If this ever starts
      // passing, primary drifted off the logo.
      expect(
        contrast(AppColors.white, AppColors.primary),
        lessThan(_aaText),
        reason:
            'primary is the logotype tone (2.97:1). If it became white-safe it '
            'would no longer match the artwork — use primaryAction for UI.',
      );
    });

    test('primaryAction carries white LABEL text at AA', () {
      expectContrast(
        AppColors.white,
        AppColors.primaryAction,
        _aaText,
        because: 'every filled CTA puts white text on primaryAction',
      );
    });

    test('primaryAction carries white icons at AA non-text', () {
      expectContrast(
        AppColors.white,
        AppColors.primaryAction,
        _aaLarge,
        because: 'the Scan FAB is a white glyph on primaryAction',
      );
    });

    test('primaryDark is emerald TEXT on light surfaces at AA', () {
      expectContrast(
        AppColors.primaryDark,
        AppSemanticColors.light.surface,
        _aaText,
        because: 'links and emerald labels on white use primaryDark',
      );
      expectContrast(
        AppColors.primaryDark,
        AppSemanticColors.light.background,
        _aaText,
        because: 'emerald text also lands on the page background',
      );
    });

    test('primaryLight is the emerald that survives on dark surfaces', () {
      expectContrast(
        AppColors.primaryLight,
        AppSemanticColors.dark.surface,
        _aaText,
        because: 'dark-mode emerald text/marks use primaryLight',
      );
    });
  });

  group('text is AA on every surface it lands on — light', () {
    const c = AppSemanticColors.light;
    for (final surface in <(String, Color)>[
      ('background', c.background),
      ('surface', c.surface),
      ('card', c.card),
      ('surfaceMuted', c.surfaceMuted),
    ]) {
      test('textPrimary on ${surface.$1}', () {
        expectContrast(c.textPrimary, surface.$2, _aaText,
            because: 'body text on ${surface.$1}');
      });
      test('textSecondary on ${surface.$1}', () {
        expectContrast(c.textSecondary, surface.$2, _aaText,
            because: 'supporting text on ${surface.$1}');
      });
      test('textMuted on ${surface.$1}', () {
        expectContrast(c.textMuted, surface.$2, _aaText,
            because: 'micro-labels on ${surface.$1} are still normal-size text');
      });
    }
  });

  group('text is AA on every surface it lands on — dark', () {
    const c = AppSemanticColors.dark;
    for (final surface in <(String, Color)>[
      ('background', c.background),
      ('surface', c.surface),
      ('card', c.card),
      ('surfaceMuted', c.surfaceMuted),
    ]) {
      test('textPrimary on ${surface.$1}', () {
        expectContrast(c.textPrimary, surface.$2, _aaText,
            because: 'body text on ${surface.$1}');
      });
      test('textSecondary on ${surface.$1}', () {
        expectContrast(c.textSecondary, surface.$2, _aaText,
            because: 'supporting text on ${surface.$1}');
      });
      test('textMuted on ${surface.$1}', () {
        expectContrast(c.textMuted, surface.$2, _aaText,
            because: 'micro-labels on ${surface.$1} are still normal-size text');
      });
    }
  });

  group('every container pairs with an AA on-color', () {
    for (final theme in <(String, AppSemanticColors)>[
      ('light', AppSemanticColors.light),
      ('dark', AppSemanticColors.dark),
    ]) {
      final name = theme.$1;
      final c = theme.$2;
      final pairs = <(String, Color, Color)>[
        ('primary', c.onPrimaryContainer, c.primaryContainer),
        ('success', c.onSuccessContainer, c.successContainer),
        ('warning', c.onWarningContainer, c.warningContainer),
        ('error', c.onErrorContainer, c.errorContainer),
        ('info', c.onInfoContainer, c.infoContainer),
        ('streak', c.onStreakContainer, c.streakContainer),
        ('xp', c.onXpContainer, c.xpContainer),
      ];
      for (final p in pairs) {
        test('on${p.$1}Container on ${p.$1}Container ($name)', () {
          expectContrast(p.$2, p.$3, _aaText,
              because: '$name ${p.$1} container text');
        });
      }
    }
  });

  // Material paints InputDecorator's error label and focused-error border with
  // colorScheme.error, which app_theme wires to `errorText`. A brightness-
  // agnostic red cannot serve that role: AppColors.error is 5.96:1 on white but
  // 2.87:1 on the dark surface, so form validation errors were unreadable in
  // dark mode.
  group('error TEXT is legible on the page surface in both themes', () {
    test('light', () {
      expectContrast(
        AppSemanticColors.light.errorText,
        AppSemanticColors.light.surface,
        _aaText,
        because: 'form validation error text on a light card',
      );
    });
    test('dark', () {
      expectContrast(
        AppSemanticColors.dark.errorText,
        AppSemanticColors.dark.surface,
        _aaText,
        because: 'form validation error text on a dark card',
      );
    });
    test('and on the page background too', () {
      expectContrast(AppSemanticColors.light.errorText,
          AppSemanticColors.light.background, _aaText,
          because: 'light background');
      expectContrast(AppSemanticColors.dark.errorText,
          AppSemanticColors.dark.background, _aaText,
          because: 'dark background');
    });
  });

  group('status hues clear AA where they are used as text/fills', () {
    test('error carries white text', () {
      expectContrast(AppColors.white, AppColors.error, _aaText,
          because: 'destructive buttons are white on error');
    });
    test('error reads as text on white', () {
      expectContrast(AppColors.error, AppSemanticColors.light.surface, _aaText,
          because: 'inline error text on a card');
    });
    test('warning carries white text', () {
      expectContrast(AppColors.white, AppColors.warning, _aaText,
          because: 'warning fills carry white labels');
    });
    test('info carries white text', () {
      expectContrast(AppColors.white, AppColors.info, _aaText,
          because: 'info fills carry white labels');
    });
    test('secondary carries white text', () {
      expectContrast(AppColors.white, AppColors.secondary, _aaText,
          because: 'the indigo accent is used as a filled chip');
    });
    test('gold is a surface, so ink sits on it', () {
      expectContrast(AppColors.onGold, AppColors.gold, _aaText,
          because: 'premium badges are ink-on-gold');
    });
  });

  // The removed AppColors.primaryGradient filled every primary CTA with a
  // #34D399 top stop, putting white label text at 1.92:1 — worse than any solid
  // tone in the palette. It was simultaneously the worst accessibility defect in
  // the app and the brief's "excessive gradient" violation. Filled controls use
  // solid primaryAction.
  //
  // The real tripwire is structural: this suite cannot reference a deleted
  // symbol (that would not compile), so instead it asserts the *property* that
  // made the gradient wrong — every emerald light enough to have been its top
  // stop must be too light to carry white text, which is why no such tone may
  // ever be a fill under a white label.
  group('the brand does not gradient its emerald', () {
    test('the pale ramp steps are not white-text safe — they are not fills', () {
      for (final step in <(String, Color)>[
        ('emerald200', AppColors.emerald200),
        ('emerald300', AppColors.emerald300),
        ('emerald400', AppColors.emerald400),
      ]) {
        expect(
          contrast(AppColors.white, step.$2),
          lessThan(_aaLarge),
          reason:
              '${step.$1} is a tint, not a fill. If white ever passes on it, '
              'someone has darkened the ramp and the tint scale is broken.',
        );
      }
    });

    test('primaryAction is the lightest emerald white text may sit on', () {
      // i.e. the ramp step directly above it must fail. This pins the split:
      // there is exactly one correct fill, and it is not a gradient's top stop.
      expect(contrast(AppColors.white, AppColors.primaryAction),
          greaterThanOrEqualTo(_aaText));
      expect(contrast(AppColors.white, AppColors.emerald500),
          lessThan(_aaText));
    });
  });
}
