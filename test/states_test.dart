// Step 8 — all states (§9). The honest, directive failure/empty surfaces:
// camera-permission (Settings deep-link) + any-camera-failure message, the
// result-tab empties that carry a real CTA, and the offline-vs-generic solve
// error. The scanner ScanErrorKind mapping is unit-tested in scanner_test.dart;
// the couldn't-verify expansion in result_stepper_test.dart.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/backend/functions_client.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/result/application/solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/result_screen.dart';
import 'package:matheasy/features/result/presentation/tabs/explain_tab.dart';
import 'package:matheasy/features/result/presentation/tabs/practice_tab.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/scan/presentation/widgets/camera_viewport.dart';

const _eq = DetectedEquation(
  latex: '2x + 5 = 13',
  confidence: 0.9,
  source: ScanSource.camera,
  kind: EquationKind.linear,
);

/// A solver that always throws — to drive the result screen's error branch.
class _ThrowingSolver implements SolverService {
  _ThrowingSolver(this.error);
  final Object error;

  @override
  Future<ResultData> solve(DetectedEquation equation) async => throw error;
}

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: Scaffold(body: child)),
    );

void main() {
  group('camera unavailable (§9)', () {
    testWidgets('permission denied → directive voice + Open Settings deep-link',
        (tester) async {
      var openedSettings = false;
      await _pump(
        tester,
        CameraViewport(
          controller: null,
          error: CameraException('CameraAccessDenied', 'denied'),
          onEnableCamera: () {},
          onOpenSettings: () => openedSettings = true,
          onType: () {},
        ),
      );
      await tester.pump();

      // Directive, not an apology or a bare status label.
      expect(
        find.text('Matheasy needs the camera to scan problems'),
        findsOneWidget,
      );
      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Type it in'), findsOneWidget); // never a dead end

      await tester.tap(find.text('Open Settings'));
      expect(openedSettings, isTrue);
    });

    testWidgets('a non-permission camera failure is explained, not blank',
        (tester) async {
      await _pump(
        tester,
        CameraViewport(
          controller: null,
          error: CameraException('CameraAccessRestricted', 'restricted'),
          onEnableCamera: () {},
          onOpenSettings: () {},
          onType: () {},
        ),
      );
      await tester.pump();

      expect(find.text('Your camera isn’t available'), findsOneWidget);
      expect(find.text('Type it in'), findsOneWidget);
      // Not the permission copy — this isn't a denial.
      expect(find.text('Open Settings'), findsNothing);
    });
  });

  group('result-tab empties carry a real next action (§9)', () {
    testWidgets('empty Explain offers Ask Matheasy (not a fake "loading")',
        (tester) async {
      var asked = false;
      await _pump(
        tester,
        SingleChildScrollView(
          child: ExplainTab(
            explanations: const [],
            onAskMatheasy: () => asked = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('talk you through'), findsOneWidget);
      await tester.tap(find.text('Ask Matheasy'));
      expect(asked, isTrue);
    });

    testWidgets('empty Practice actually surfaces the Generate button',
        (tester) async {
      var generated = false;
      await _pump(
        tester,
        SingleChildScrollView(
          child: PracticeTab(
            questions: const [],
            onGenerateMore: () => generated = true,
            onOpenQuestion: () {},
          ),
        ),
      );
      await tester.pump();

      // The broken affordance is fixed: the empty copy has a button to tap.
      await tester.tap(find.text('Generate practice'));
      expect(generated, isTrue);
    });
  });

  group('solve error distinguishes offline (§9)', () {
    Future<void> pumpResult(WidgetTester tester, Object error) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            solverServiceProvider.overrideWithValue(_ThrowingSolver(error)),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ResultScreen(equation: _eq),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('offline backend error → "You\'re offline" + what still works',
        (tester) async {
      await pumpResult(
        tester,
        const BackendException('unavailable', code: 'unavailable'),
      );
      expect(find.text("You're offline"), findsOneWidget);
      expect(find.textContaining('saved solutions still open offline'),
          findsOneWidget);
    });

    testWidgets('a non-offline failure gets the calm generic error, not offline',
        (tester) async {
      await pumpResult(tester, StateError('boom'));
      expect(find.text("You're offline"), findsNothing);
      expect(find.text("That one didn't go through"), findsOneWidget);
    });
  });
}
