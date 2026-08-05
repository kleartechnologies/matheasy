import 'package:flutter/widgets.dart';

import '../../../core/localization/l10n_extension.dart';
import '../domain/detected_equation.dart';

/// The student-facing name of a problem category, in their language.
///
/// Lives in the presentation layer rather than on the enum because the enum is
/// domain: it is serialized into history and compared for equality, and giving
/// it a `BuildContext` would drag localization into a type that has no screen.
extension EquationKindL10n on EquationKind {
  String labelOf(BuildContext context) {
    final l10n = context.l10n;
    return switch (this) {
      EquationKind.linear => l10n.problemKindLinear,
      EquationKind.quadratic => l10n.problemKindQuadratic,
      EquationKind.fraction => l10n.problemKindFraction,
      EquationKind.expression => l10n.problemKindExpression,
      EquationKind.trigonometry => l10n.problemKindTrigonometry,
      EquationKind.geometry => l10n.problemKindGeometry,
    };
  }
}
