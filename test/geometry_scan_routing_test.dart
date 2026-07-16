// Scanned geometry → the diagram-first player (Pro-gated).
//
// A geometry problem the recognizer extracted structured facts for should, for
// a Pro user, render the GeometryVisualPlayer DIRECTLY from those facts —
// bypassing the geometry-blind solver entirely (no loading/solve). A free user
// falls through to the normal solve flow, keeping the visual feature Pro-only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/core/widgets/widgets.dart';
import 'package:matheasy/features/result/application/solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/result_screen.dart';
import 'package:matheasy/features/result/presentation/widgets/visual/geometry_visual_player.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/subscription/application/subscription_controller.dart';

/// A geometry scan whose recognizer extracted a solvable Pythagoras problem.
const _geoEquation = DetectedEquation(
  latex: r'\text{right triangle, legs 6 and 8, find } x',
  confidence: 0.95,
  source: ScanSource.camera,
  kind: EquationKind.geometry,
  geometry: {
    'kind': 'rightTrianglePythagoras',
    'unknown': 'x',
    'sides': [
      {'label': 'a', 'role': 'leg', 'value': 6},
      {'label': 'b', 'role': 'leg', 'value': 8},
      {'label': 'x', 'role': 'hypotenuse'},
    ],
  },
);

/// A solver that must NOT be reached on the Pro geometry path — if it is, the
/// test surfaces it (the whole point is to bypass the geometry-blind solver).
class _ExplodingSolver implements SolverService {
  @override
  Future<ResultData> solve(DetectedEquation equation) async =>
      throw StateError('solver should be bypassed for scanned geometry');
}

Future<void> _pump(WidgetTester tester, {required bool pro}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        isProProvider.overrideWithValue(pro),
        solverServiceProvider.overrideWithValue(_ExplodingSolver()),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ResultScreen(equation: _geoEquation),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Pro: scanned geometry renders the player, solver bypassed',
      (tester) async {
    await _pump(tester, pro: true);
    await tester.pump();

    expect(find.byType(GeometryVisualPlayer), findsOneWidget);
    // The scanned photo card is absent here (no bytes), but the diagram is shown
    // and the step strip is live.
    expect(find.textContaining('STEP 1 OF 4'), findsOneWidget);
    // Solver was never invoked (no loading state, no thrown StateError surfaced).
    expect(find.byType(LoadingState), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Free: scanned geometry does NOT show the player (Pro-gated)',
      (tester) async {
    await _pump(tester, pro: false);
    await tester.pump();
    // Falls through to the normal solve flow (which here would hit the solver);
    // the point is only that the premium player is not shown to free users.
    expect(find.byType(GeometryVisualPlayer), findsNothing);
  });
}
