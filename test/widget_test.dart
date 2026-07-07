// Stage 2 tests — onboarding experience + navigation.
//
// Covers: pure guard logic (incl. splash exemption), deep-link parsing, the
// onboarding flow controller, the splash → onboarding hand-off, and the shell
// once onboarding is complete. pump() (not pumpAndSettle) is used because
// mascot/typing animations loop forever.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/app.dart';
import 'package:matheasy/core/router/app_routes.dart';
import 'package:matheasy/core/router/deep_link_parser.dart';
import 'package:matheasy/core/router/route_guard.dart';
import 'package:matheasy/core/session/app_session.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/core/widgets/widgets.dart';
import 'package:matheasy/features/home/application/home_controller.dart';
import 'package:matheasy/features/home/domain/home_models.dart';
import 'package:matheasy/features/home/presentation/home_screen.dart';
import 'package:matheasy/features/onboarding/application/onboarding_controller.dart';
import 'package:matheasy/features/onboarding/domain/onboarding_models.dart';
import 'package:matheasy/features/result/application/result_controller.dart';
import 'package:matheasy/features/result/application/solver_service.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/result/presentation/result_screen.dart';
import 'package:matheasy/features/scan/application/scanner_controller.dart';
import 'package:matheasy/features/scan/application/scanner_service.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/scan/domain/scan_state.dart';
import 'package:matheasy/features/scan/presentation/scanner_screen.dart';
import 'package:matheasy/features/splash/presentation/splash_screen.dart';

import 'support/fake_auth_service.dart';

/// Boots the full app and advances past the splash hand-off.
///
/// [signedIn] restores a Google session; without it the session resolves to
/// unauthenticated. Local preferences + auth are provided by [sessionContainer]
/// so the guard has real (fake-backed) state to route on.
Future<void> _bootApp(
  WidgetTester tester, {
  bool onboarded = false,
  bool signedIn = false,
}) async {
  final container = await sessionContainer(
    onboarded: onboarded,
    signedInUser: signedIn ? googleTestUser() : null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const MatheasyApp()),
  );
  await tester.pump(); // build splash + resolve auth stream
  await tester.pump(SplashScreen.minDisplay); // fire splash timer → route on
  await tester.pump(); // router redirect
  await tester.pump(const Duration(seconds: 1)); // settle splash→target route
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('DeepLinkParser', () {
    test('resolves custom-scheme hosts', () {
      expect(
          DeepLinkParser.resolve(Uri.parse('matheasy://scan')), AppRoutes.scan);
      expect(DeepLinkParser.resolve(Uri.parse('matheasy://paywall')),
          AppRoutes.paywall);
    });

    test('returns null for in-app and unknown links', () {
      expect(DeepLinkParser.resolve(Uri.parse('/home')), isNull);
      expect(DeepLinkParser.resolve(Uri.parse('matheasy://nope')), isNull);
    });
  });

  group('RouteGuard', () {
    String? guard({
      required String location,
      required Uri uri,
      AuthStatus auth = AuthStatus.authenticated,
      bool onboarded = true,
      bool premium = false,
    }) =>
        RouteGuard.evaluate(
          matchedLocation: location,
          uri: uri,
          authStatus: auth,
          onboardingComplete: onboarded,
          isPremium: premium,
        );

    test('splash is never redirected', () {
      expect(
        guard(
          location: AppRoutes.splash,
          uri: Uri.parse(AppRoutes.splash),
          onboarded: false,
          auth: AuthStatus.unauthenticated,
        ),
        isNull,
      );
    });

    test('incomplete onboarding redirects to /onboarding', () {
      expect(
        guard(location: '/home', uri: Uri.parse('/home'), onboarded: false),
        AppRoutes.onboarding,
      );
    });

    test('unauthenticated is sent to /auth', () {
      expect(
        guard(
          location: '/home',
          uri: Uri.parse('/home'),
          auth: AuthStatus.unauthenticated,
        ),
        AppRoutes.auth,
      );
    });

    test('happy path allows navigation', () {
      expect(guard(location: '/home', uri: Uri.parse('/home')), isNull);
    });
  });

  group('OnboardingFlowController', () {
    test('collects level, topics (toggle) and goal', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final ctrl =
          container.read(onboardingFlowControllerProvider.notifier)
            ..selectLevel(StudyLevel.spm)
            ..toggleTopic(MathTopic.algebra)
            ..toggleTopic(MathTopic.calculus)
            ..toggleTopic(MathTopic.algebra) // toggles algebra back off
            ..selectGoal(DailyGoal.min10);

      final data = container.read(onboardingFlowControllerProvider);
      expect(data.level, StudyLevel.spm);
      expect(data.topics, {MathTopic.calculus});
      expect(data.goal, DailyGoal.min10);
      expect(data.hasLevel && data.hasTopics && data.hasGoal, isTrue);
      expect(ctrl, isNotNull);
    });
  });

  group('Boot flow', () {
    testWidgets('splash hands new users to onboarding', (tester) async {
      await _bootApp(tester);
      expect(find.text('Make Math Easy'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('advancing onboarding shows the next page', (tester) async {
      await _bootApp(tester);
      await tester.tap(find.text('Get Started'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Snap Any Math Question'), findsOneWidget);
    });

    testWidgets('onboarded users boot into the Home dashboard', (tester) async {
      await _bootApp(tester, onboarded: true, signedIn: true);
      expect(find.byType(AppTabBar), findsOneWidget);
      expect(find.text('Sarah'), findsOneWidget); // header greeting name
    });

    testWidgets('tapping Practice tab switches branch', (tester) async {
      await _bootApp(tester, onboarded: true, signedIn: true);
      final practiceTab = find.descendant(
        of: find.byType(AppTabBar),
        matching: find.byIcon(Icons.fitness_center_rounded),
      );
      await tester.tap(practiceTab);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(
        find.text('Adaptive practice and topic mastery arrive in Stage 8.'),
        findsOneWidget,
      );
    });
  });

  group('Home', () {
    test('greetingForHour maps time of day', () {
      expect(greetingForHour(8), 'Good morning');
      expect(greetingForHour(14), 'Good afternoon');
      expect(greetingForHour(20), 'Good evening');
    });

    test('mock controller yields rich returning-user data', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final data = container.read(homeControllerProvider);
      expect(data.userName, 'Sarah');
      expect(data.streak.current, 12);
      expect(data.continueCourses, hasLength(3));
      expect(data.weakTopics, hasLength(2)); // defaults when no onboarding
      expect(data.isFirstDay, isFalse);
    });

    test('personalizes weak topics from onboarding answers', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(onboardingFlowControllerProvider.notifier)
        ..toggleTopic(MathTopic.geometry)
        ..toggleTopic(MathTopic.calculus);

      final data = container.read(homeControllerProvider);
      final labels = data.weakTopics.map((t) => t.label).toList();
      expect(labels, contains('Geometry'));
      expect(labels, contains('Calculus'));
    });

    testWidgets('first-day dashboard shows starter content', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeControllerProvider.overrideWith(_FirstDayHomeController.new),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      // First-day CTA (only present when isFirstDay) proves the empty-state path.
      expect(find.text('Start learning'), findsOneWidget);
    });
  });

  group('Scanner', () {
    test('mock recognizer returns source-specific samples', () async {
      const service = MockScannerService();
      final camera = await service.recognize(ScanSource.camera);
      expect(camera.latex, r'2x + 5 = 13');
      expect(camera.kind, EquationKind.linear);

      final gallery = await service.recognize(ScanSource.gallery);
      expect(gallery.kind, EquationKind.quadratic);
    });

    test('controller drives capture → confirm → retake', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(scannerControllerProvider, (_, _) {});
      addTearDown(sub.close);

      expect(container.read(scannerControllerProvider), isA<ScanIdle>());

      await container
          .read(scannerControllerProvider.notifier)
          .capture(ScanSource.gallery);
      final captured = container.read(scannerControllerProvider);
      expect(captured, isA<ScanCaptured>());
      expect((captured as ScanCaptured).equation.kind, EquationKind.quadratic);

      container.read(scannerControllerProvider.notifier).confirm();
      expect(container.read(scannerControllerProvider), isA<ScanProcessing>());

      container.read(scannerControllerProvider.notifier).retake();
      expect(container.read(scannerControllerProvider), isA<ScanIdle>());
    });

    testWidgets('capture shows the confirmation sheet', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ScannerScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Scan a problem'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.photo_library_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // recognize delay

      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
      expect(find.text('Quadratic equation'), findsOneWidget);

      // Let the pending live-detect timer fire so none is left at teardown.
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('Result', () {
    const linear = DetectedEquation(
      latex: r'2x + 5 = 13',
      confidence: 0.99,
      source: ScanSource.camera,
      kind: EquationKind.linear,
    );

    test('tab memory persists per problem but resets for a new one', () {
      const quadratic = DetectedEquation(
        latex: r'x^2 + 5x + 6 = 0',
        confidence: 0.97,
        source: ScanSource.camera,
        kind: EquationKind.quadratic,
      );
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final tab = container.read(resultTabProvider.notifier);

      tab
        ..syncFor(linear)
        ..select(2);
      expect(container.read(resultTabProvider), 2);

      // Re-opening the SAME problem keeps the remembered tab.
      tab.syncFor(linear);
      expect(container.read(resultTabProvider), 2);

      // A DIFFERENT problem resets to the Solution tab.
      tab.syncFor(quadratic);
      expect(container.read(resultTabProvider), 0);
    });

    test('mock solver builds a full linear solution', () async {
      final data = await const MockSolverService().solve(linear);
      expect(data.type, ResultType.linear);
      expect(data.answerLatex, r'x = 4');
      expect(data.steps, hasLength(3));
      expect(data.explanations, hasLength(3));
      expect(data.methods.where((m) => m.recommended), isNotEmpty);
      expect(data.practice, isNotEmpty);
    });

    test('mock solver classifies quadratic and fraction', () async {
      const service = MockSolverService();
      final quadratic = await service.solve(const DetectedEquation(
        latex: r'x^2 + 5x + 6 = 0',
        confidence: 0.97,
        source: ScanSource.camera,
        kind: EquationKind.quadratic,
      ));
      final fraction = await service.solve(const DetectedEquation(
        latex: r'\frac{3}{4} + \frac{1}{2}',
        confidence: 0.96,
        source: ScanSource.gallery,
        kind: EquationKind.fraction,
      ));
      expect(quadratic.type, ResultType.quadratic);
      expect(fraction.type, ResultType.fraction);
    });

    testWidgets('screen solves and renders the solution', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ResultScreen(equation: linear),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Numi is solving your problem…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600)); // solve delay
      expect(find.text('Linear Equation'), findsOneWidget);
      expect(find.text('FINAL ANSWER'), findsOneWidget);
      expect(find.text('Subtract 5 from both sides'), findsOneWidget);
    });

    testWidgets('switching to Methods reveals the recommended badge',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ResultScreen(equation: linear),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(find.text('Methods'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('RECOMMENDED'), findsOneWidget);
    });
  });
}

/// Forces the first-day dataset for the empty-state test.
class _FirstDayHomeController extends HomeController {
  @override
  HomeData build() => HomeMock.firstDay();
}
