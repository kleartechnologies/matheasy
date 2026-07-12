// Stage 2 tests — onboarding experience + navigation.
//
// Covers: pure guard logic (incl. splash exemption), deep-link parsing, the
// onboarding flow controller, the splash → onboarding hand-off, and the shell
// once onboarding is complete. pump() (not pumpAndSettle) is used because
// brand and typing animations loop forever.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/app.dart';
import 'package:matheasy/core/router/app_routes.dart';
import 'package:matheasy/core/router/deep_link_parser.dart';
import 'package:matheasy/core/router/route_guard.dart';
import 'package:matheasy/core/session/app_session.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/core/widgets/widgets.dart';
import 'package:matheasy/features/auth/application/auth_controller.dart';
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
import 'package:matheasy/features/scan/presentation/manual_input_screen.dart';
import 'package:matheasy/features/scan/presentation/scanner_screen.dart';
import 'package:matheasy/features/scan/presentation/widgets/capture_confirmation.dart';
import 'package:matheasy/features/splash/presentation/splash_screen.dart';
import 'package:matheasy/features/subscription/application/usage_controller.dart';
import 'package:matheasy/features/subscription/domain/usage_counts.dart';
import 'package:matheasy/features/subscription/domain/usage_quota.dart';
import 'package:matheasy/features/subscription/domain/usage_snapshot.dart';

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
      // The greeting shows the REAL signed-in account name (googleTestUser),
      // not the old hardcoded 'Sarah' mock.
      expect(find.text('Sarah Lee'), findsOneWidget);
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
      // The real Practice dashboard (Stage 8) renders its XP level header.
      expect(find.text('Level 1'), findsOneWidget);
    });
  });

  group('Home', () {
    test('greetingForHour maps time of day', () {
      expect(greetingForHour(8), 'Good morning');
      expect(greetingForHour(14), 'Good afternoon');
      expect(greetingForHour(20), 'Good evening');
    });

    testWidgets('a signed-in user sees their REAL name on Home, never the '
        'demo mock', (tester) async {
      // The greeting name now comes from the profile (real account), not a
      // hardcoded 'Sarah'.
      final container = await sessionContainer(signedInUser: appleTestUser());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Alex Kim'), findsOneWidget);
      expect(find.text('Sarah'), findsNothing); // the old mock is gone
    });

    testWidgets('a brand-new user gets an HONEST first-day dashboard, not the '
        'returning-user mock', (tester) async {
      // Fresh account (no name, no practice history) + empty local prefs.
      final container = await sessionContainer(signedInUser: newAccountUser());
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      final data = container.read(homeControllerProvider);
      expect(data.userName, 'Learner'); // honest fallback, not 'Sarah'
      expect(data.isFirstDay, isTrue);
      expect(data.streak.current, 0); // not a fabricated 12-day streak
      expect(data.continueCourses, isEmpty); // not 3 fake courses → card hidden
      expect(data.weakTopics, isEmpty); // no fabricated accuracies → card hidden
      expect(data.todayChallenge!.done, 0); // honest, not a fake "2 of 5"
    });

    test('Home rebuilds for the new user across the sign-in boundary '
        '(the signup fix)', () async {
      // Start signed OUT, then sign in — the real reactive chain
      // (auth → currentUser → profile → home) must repoint Home at the new user.
      final container = await sessionContainer();
      addTearDown(container.dispose);
      final sub = container.listen(
        homeControllerProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(container.read(homeControllerProvider).userName, isNot('Sarah'));

      await container.read(authControllerProvider.notifier).signInWithApple();

      // No manual invalidation anywhere — the watch(profile→currentUser) chain
      // rebuilds Home on its own. This is exactly what was broken before.
      expect(container.read(homeControllerProvider).userName, 'Alex Kim');
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

    test('controller drives recognize → confirm → retake', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(scannerControllerProvider, (_, _) {});
      addTearDown(sub.close);

      expect(container.read(scannerControllerProvider), isA<ScanIdle>());

      await container
          .read(scannerControllerProvider.notifier)
          .recognize(ScanSource.gallery, imageBytes: Uint8List.fromList([1, 2]));
      final captured = container.read(scannerControllerProvider);
      expect(captured, isA<ScanCaptured>());
      expect((captured as ScanCaptured).equation.kind, EquationKind.quadratic);

      container.read(scannerControllerProvider.notifier).confirm();
      expect(container.read(scannerControllerProvider), isA<ScanComplete>());

      container.read(scannerControllerProvider.notifier).retake();
      expect(container.read(scannerControllerProvider), isA<ScanIdle>());
    });

    testWidgets('renders chrome and stays usable when no camera is available',
        (tester) async {
      // In the test binding the camera plugin isn't registered, so the screen
      // must fall back gracefully (no crash) and keep gallery / type reachable.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ScannerScreen(),
          ),
        ),
      );
      await tester.pump(); // let _initCamera() reject
      await tester.pump();

      expect(find.text('Scan a problem'), findsOneWidget);
      expect(find.byIcon(Icons.photo_library_rounded), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_rounded), findsOneWidget);
    });

    testWidgets('a capped free user is sent to the paywall before capturing',
        (tester) async {
      // Gallery works without a live camera, so it's the tappable path in tests.
      // A capped user tapping it must hit the EXISTING paywall — never the
      // picker — so no scan is spent (spec §2/§10 pre-scan gate).
      final router = GoRouter(
        initialLocation: '/scan',
        routes: [
          GoRoute(path: '/scan', builder: (_, _) => const ScannerScreen()),
          GoRoute(
            path: AppRoutes.paywall,
            builder: (_, _) => const Text('PAYWALL_STUB'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            usageSnapshotProvider.overrideWith(
              (ref) => const UsageSnapshot(
                counts: UsageCounts(scansUsed: 5), // at the free cap
                quota: UsageQuota.free,
                isPro: false,
              ),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump(); // let _initCamera() reject (no plugin in tests)
      await tester.pump();

      await tester.tap(find.byIcon(Icons.photo_library_rounded));
      await tester.pump(); // start the route transition
      await tester.pump(const Duration(milliseconds: 600)); // finish it

      expect(find.text('PAYWALL_STUB'), findsOneWidget);
    });

    testWidgets('detected equation is tappable-to-edit; low confidence prompts a '
        'check (§3)', (tester) async {
      var edited = false;
      const lowConf = DetectedEquation(
        latex: r'5x^2 + 3x - 2 = 0',
        confidence: 0.5, // below CaptureConfirmation.lowConfidenceThreshold
        source: ScanSource.camera,
        kind: EquationKind.quadratic,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: CaptureConfirmation(
              equation: lowConf,
              onRetake: () {},
              onContinue: () {},
              onEdit: () => edited = true,
            ),
          ),
        ),
      );

      // Low confidence → a "check this" prompt, not a confident "detected".
      expect(find.textContaining('CHECK THIS'), findsOneWidget);
      expect(find.textContaining('tap the problem to fix'), findsOneWidget);
      // The primary action reads "Solve".
      expect(find.text('Solve'), findsOneWidget);
      // The equation itself is tappable → opens the editor.
      await tester.tap(find.byIcon(Icons.edit_rounded));
      expect(edited, isTrue);
    });

    testWidgets('the editor pre-fills with the recognized LaTeX in edit mode (§3)',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ManualInputScreen(
              args: ManualInputArgs(
                initialLatex: r'2x + 5 = 13',
                editMode: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Pre-filled with the recognized LaTeX (not blank) and in edit mode.
      expect(find.text(r'2x + 5 = 13'), findsOneWidget);
      expect(find.text('Fix the problem'), findsOneWidget);
      expect(find.text('Use this'), findsOneWidget); // not "Solve"
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

    testWidgets('screen solves; steps reveal one at a time (§5)', (tester) async {
      // Keep the default 800 width (no IntrinsicHeight sub-pixel overflow) but
      // taller, so "Reveal all" is on-screen and tappable.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ResultScreen(equation: linear),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Matheasy is solving your problem…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 600)); // solve delay
      expect(find.text('Linear Equation'), findsOneWidget);
      expect(find.text('FINAL ANSWER'), findsOneWidget);
      // One-at-a-time (spec §5): the first step shows; a later one is hidden
      // behind "Next step".
      expect(find.text('Start with the equation'), findsOneWidget);
      expect(find.text('Subtract 5 from both sides'), findsNothing);
      expect(find.textContaining('Next step'), findsOneWidget);

      // Reveal all → the later step appears.
      await tester.tap(find.text('Reveal all'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
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
