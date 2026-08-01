import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_colors.dart';
import 'package:matheasy/core/theme/app_semantic_colors.dart';
import 'package:matheasy/core/theme/math_semantics.dart';

/// WCAG 2.x relative luminance of an opaque sRGB color.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final hi = math.max(_luminance(a), _luminance(b));
  final lo = math.min(_luminance(a), _luminance(b));
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The semantic colour system (spec Part 7) is a VOCABULARY: a student learns
  // "orange = the operation happening now" once and reads it everywhere. That
  // only works if the colours are (a) legible on every surface maths lands on
  // and (b) distinguishable from each other.
  group('MathRole colours', () {
    // The surfaces a highlighted equation actually renders on — read from the
    // tokens, so moving a surface re-runs this check against the new value.
    final lightSurfaces = <String, Color>{
      'the chat bubble': AppSemanticColors.light.surface,
      'the page': AppSemanticColors.light.background,
      'the focus panel': AppSemanticColors.light.surfaceMuted,
    };
    final darkSurfaces = <String, Color>{
      'the chat bubble': AppSemanticColors.dark.surface,
      'the page': AppSemanticColors.dark.background,
      'the focus panel': AppSemanticColors.dark.surfaceMuted,
    };

    test('every role clears AA on every surface it can land on', () {
      for (final role in MathRole.values) {
        final light = role.color(AppSemanticColors.light, isDark: false);
        for (final entry in lightSurfaces.entries) {
          final ratio = _contrast(light, entry.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${role.name} on ${entry.key} (light) — '
                'got ${ratio.toStringAsFixed(2)}:1, need 4.5:1',
          );
        }
        final dark = role.color(AppSemanticColors.dark, isDark: true);
        for (final entry in darkSurfaces.entries) {
          final ratio = _contrast(dark, entry.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${role.name} on ${entry.key} (dark) — '
                'got ${ratio.toStringAsFixed(2)}:1, need 4.5:1',
          );
        }
      }
    });

    test('no two roles resolve to the same colour', () {
      for (final isDark in [false, true]) {
        final scheme = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
        final seen = <int, MathRole>{};
        for (final role in MathRole.values) {
          final value = role.color(scheme, isDark: isDark).toARGB32();
          expect(
            seen[value],
            isNull,
            reason: '${role.name} and ${seen[value]?.name} share a colour '
                '(${isDark ? 'dark' : 'light'}) — the vocabulary collapses',
          );
          seen[value] = role;
        }
      }
    });

    // The logo emerald is 2.97:1 on white. It is the identity, not a text
    // colour, and a highlighted answer is text.
    test('the answer role never uses the identity emerald', () {
      expect(
        MathRole.answer.color(AppSemanticColors.light, isDark: false),
        isNot(AppColors.primary),
      );
      expect(
        MathRole.answer.color(AppSemanticColors.dark, isDark: true),
        isNot(AppColors.primary),
      );
    });
  });

  group('mathRoleHex', () {
    test('renders the #RRGGBB form \\textcolor understands', () {
      expect(mathRoleHex(const Color(0xFF058446)), '#058446');
      expect(mathRoleHex(const Color(0xFF000000)), '#000000');
      expect(mathRoleHex(const Color(0xFFFFFFFF)), '#ffffff');
    });

    test('drops alpha rather than emitting an 8-digit value LaTeX cannot read',
        () {
      expect(mathRoleHex(const Color(0x80058446)), '#058446');
    });
  });

  group('MathRole.parse', () {
    test('reads the wire names', () {
      expect(MathRole.parse('answer'), MathRole.answer);
      expect(MathRole.parse('operation'), MathRole.operation);
      expect(MathRole.parse(' Unknown '), MathRole.unknown);
    });

    // An unknown role must not become a *meaningful* colour by accident:
    // "aside" is the one role that can never mislead.
    test('degrades an unknown role to aside, never to a claim', () {
      expect(MathRole.parse(null), MathRole.aside);
      expect(MathRole.parse(''), MathRole.aside);
      expect(MathRole.parse('correct'), MathRole.aside);
    });
  });
}
