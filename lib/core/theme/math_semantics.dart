import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_semantic_colors.dart';

/// The semantic colour system for mathematics (spec Part 7).
///
/// Colour in an explanation is a *vocabulary*, not decoration: the same meaning
/// wears the same colour in every step, every topic, and every screen, so a
/// student learns to read "orange = the operation happening right now" once and
/// then reads it everywhere without a legend.
///
/// The six roles are fixed. Adding a seventh dilutes the vocabulary — if a new
/// idea needs a colour, it almost certainly belongs to one of these already.
enum MathRole {
  /// The correct answer, a verified result, the key takeaway.
  answer,

  /// Known values: the givens, constants, what the problem handed you.
  known,

  /// The formula being applied right now — the transformation, the operation.
  operation,

  /// The unknown: the variable being solved for, the target.
  unknown,

  /// A warning, a mistake, a sign error, an incorrect assumption.
  mistake,

  /// Supporting information — background that matters less than the rest.
  aside;

  /// The wire name, used by the tutor payload and cached content. Parsing is
  /// tolerant of case and stray whitespace; anything unrecognised is [aside],
  /// the role that can never mislead.
  static MathRole parse(String? name) {
    final key = name?.trim().toLowerCase();
    return MathRole.values.firstWhere(
      (r) => r.name == key,
      orElse: () => MathRole.aside,
    );
  }
}

/// One highlighted piece of an equation: the exact substring to tint, and what
/// it *means* (spec Parts 7–8).
@immutable
class MathHighlight {
  const MathHighlight({required this.text, required this.role});

  /// The literal substring of the equation's LaTeX to colour.
  final String text;

  /// What this piece is — the semantic role that picks the colour.
  final MathRole role;

  @override
  bool operator ==(Object other) =>
      other is MathHighlight && other.text == text && other.role == role;

  @override
  int get hashCode => Object.hash(text, role);
}

/// Resolves a [MathRole] to the colour it wears on a given surface.
///
/// Both themes are hand-checked to clear WCAG AA (4.5:1) against the surfaces
/// maths actually lands on — the chat bubble and the card — because a colour
/// that carries *meaning* has to be readable, not merely present. Ratios are
/// recorded per entry and enforced by
/// `test/core/theme/math_semantics_contrast_test.dart`.
extension MathRoleColors on MathRole {
  /// The colour for this role in the ambient theme.
  ///
  /// Reads the semantic tokens rather than hard-coding, so a theme change moves
  /// the vocabulary with it.
  Color color(AppSemanticColors colors, {required bool isDark}) {
    switch (this) {
      // Emerald as TEXT, which the brand system splits by job: `primaryDark` on
      // light, `primaryLight` on dark. Never `primary` — the logo emerald is
      // 2.97:1 and is brand art only.
      case MathRole.answer:
        return isDark ? AppColors.primaryLight : AppColors.primaryDark;
      case MathRole.known:
        return isDark ? colors.onInfoContainer : AppColors.info;
      // The deep amber, not `warning`: orange is the hardest hue to keep AA on
      // a light surface, and #B65B0C only clears it on pure white.
      case MathRole.operation:
        return isDark ? colors.onWarningContainer : AppColors.warningDeep;
      case MathRole.unknown:
        return isDark ? AppColors.secondaryLight : AppColors.secondary;
      case MathRole.mistake:
        return colors.errorText;
      case MathRole.aside:
        return colors.textSecondary;
    }
  }
}

/// `#RRGGBB` for a colour — the form `\textcolor` understands.
String mathRoleHex(Color color) {
  int channel(double v) => (v * 255).round().clamp(0, 255);
  final r = channel(color.r).toRadixString(16).padLeft(2, '0');
  final g = channel(color.g).toRadixString(16).padLeft(2, '0');
  final b = channel(color.b).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
