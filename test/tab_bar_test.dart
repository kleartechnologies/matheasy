// Widget tests for the "liquid glass" bottom navigation ([AppTabBar]): the
// frosted surface, the sliding active pill, branch-index wiring, the raised
// center Scan FAB, badges, and accessibility text scaling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/core/widgets/layout/app_tab_bar.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required int currentIndex,
  required ValueChanged<int> onTap,
  required VoidCallback onScan,
  Map<int, int> badges = const {},
  ThemeData? theme,
  double? textScale,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: Builder(
        builder: (context) {
          final scaffold = Scaffold(
            extendBody: true,
            bottomNavigationBar: AppTabBar(
              currentIndex: currentIndex,
              onTap: onTap,
              onScan: onScan,
              badges: badges,
            ),
          );
          if (textScale == null) return scaffold;
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: scaffold,
          );
        },
      ),
    ),
  );
  await tester.pump();
}

/// Horizontal center of the active pill's rendered box.
double _pillCenterX(WidgetTester tester) =>
    tester.getRect(find.byKey(AppTabBar.pillKey)).center.dx;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('AppTabBar', () {
    testWidgets('always shows a label for every side tab', (tester) async {
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () {},
      );

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Practice'), findsOneWidget);
      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
    });

    testWidgets('renders a frosted glass surface and a sliding pill',
        (tester) async {
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () {},
      );

      // The frosted blur surface.
      expect(find.byType(BackdropFilter), findsOneWidget);
      // Exactly one active pill, and it animates position (not show/hide).
      expect(find.byType(AnimatedPositioned), findsOneWidget);
      expect(find.byKey(AppTabBar.pillKey), findsOneWidget);
    });

    testWidgets('taps map to the correct navigation-shell branch index',
        (tester) async {
      final tapped = <int>[];
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: tapped.add,
        onScan: () {},
      );

      await tester.tap(find.text('Practice'));
      await tester.tap(find.text('Progress'));
      await tester.tap(find.text('Profile'));

      // Branch order is Home=0, Practice=1, Profile=2, Progress=3 — the display
      // order (Progress before Profile) must not change the branch mapping.
      expect(tapped, [1, 3, 2]);
    });

    testWidgets('the active pill sits under the selected tab, keyed by BRANCH '
        'index not display order', (tester) async {
      // Profile is branch 2 but displayed rightmost; Progress is branch 3 but
      // displayed to its left. The pill must follow the branch index, so
      // selecting branch 2 lands the pill to the RIGHT of branch 3 (2 > 3 in x
      // despite 2 < 3 numerically). This guards against re-keying by position.
      await _pumpBar(
        tester,
        currentIndex: 3,
        onTap: (_) {},
        onScan: () {},
      );
      await tester.pumpAndSettle();
      final progressLabel = tester.getCenter(find.text('Progress')).dx;
      final progressPill = _pillCenterX(tester);
      // Pill overlaps the Progress label it highlights.
      final progressRect = tester.getRect(find.byKey(AppTabBar.pillKey));
      expect(progressRect.left, lessThanOrEqualTo(progressLabel));
      expect(progressRect.right, greaterThanOrEqualTo(progressLabel));

      await _pumpBar(
        tester,
        currentIndex: 2,
        onTap: (_) {},
        onScan: () {},
      );
      await tester.pumpAndSettle();
      final profileLabel = tester.getCenter(find.text('Profile')).dx;
      final profilePill = _pillCenterX(tester);
      final profileRect = tester.getRect(find.byKey(AppTabBar.pillKey));
      expect(profileRect.left, lessThanOrEqualTo(profileLabel));
      expect(profileRect.right, greaterThanOrEqualTo(profileLabel));

      // Profile (branch 2) is highlighted to the right of Progress (branch 3).
      expect(profilePill, greaterThan(progressPill));
    });

    testWidgets('the center FAB triggers onScan, not onTap', (tester) async {
      var scans = 0;
      final tapped = <int>[];
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: tapped.add,
        onScan: () => scans++,
      );

      await tester.tap(find.byIcon(Icons.center_focus_strong_rounded));

      expect(scans, 1);
      expect(tapped, isEmpty);
    });

    testWidgets('the raised FAB stays inside the bar bounds (tappable)',
        (tester) async {
      var scans = 0;
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () => scans++,
      );

      final fab = find.byIcon(Icons.center_focus_strong_rounded);
      final barRect = tester.getRect(find.byType(AppTabBar));
      final fabRect = tester.getRect(fab);
      // The FAB rises above the glass but its whole box must remain within the
      // bar's laid-out bounds, otherwise the raised part would not receive taps.
      expect(fabRect.top, greaterThanOrEqualTo(barRect.top - 0.01));
      expect(fabRect.bottom, lessThanOrEqualTo(barRect.bottom + 0.01));

      await tester.tap(fab);
      expect(scans, 1);
    });

    testWidgets('the pill actually animates (slides) to the new tab, does not '
        'teleport', (tester) async {
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () {},
      );
      await tester.pumpAndSettle();
      final startX = _pillCenterX(tester); // Home (leftmost)

      // Re-select Profile (branch 2, rightmost) and sample mid-flight.
      await _pumpBar(
        tester,
        currentIndex: 2,
        onTap: (_) {},
        onScan: () {},
      );
      await tester.pump(); // start the animation
      await tester.pump(const Duration(milliseconds: 120)); // ~40% through 300ms
      final midX = _pillCenterX(tester);

      await tester.pumpAndSettle();
      final endX = _pillCenterX(tester); // Profile (rightmost)

      // A real slide passes strictly between the endpoints; a teleport (zero
      // duration / instant) would already equal endX at the mid sample.
      expect(endX, greaterThan(startX));
      expect(midX, greaterThan(startX));
      expect(midX, lessThan(endX));
    });

    testWidgets('a badge renders on the correct branch tab', (tester) async {
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () {},
        badges: const {2: 3}, // branch 2 = Profile
      );

      expect(find.text('3'), findsOneWidget);
      final badgeX = tester.getCenter(find.text('3')).dx;
      final profileX = tester.getCenter(find.text('Profile')).dx;
      final progressX = tester.getCenter(find.text('Progress')).dx;
      // The badge sits on Profile (branch 2), not Progress (branch 3).
      expect((badgeX - profileX).abs(), lessThan((badgeX - progressX).abs()));
    });

    testWidgets('a badge over 99 is capped to 99+', (tester) async {
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () {},
        badges: const {2: 150},
      );

      expect(find.text('99+'), findsOneWidget);
      expect(find.text('150'), findsNothing);
    });

    testWidgets('a zero/empty badge count renders nothing', (tester) async {
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () {},
        badges: const {2: 0},
      );

      expect(find.text('0'), findsNothing);
    });

    testWidgets('labels do not overflow at large accessibility text scale',
        (tester) async {
      // The fixed-height cell caps its label scale; without the cap the OS
      // accessibility font sizes overflow/clip the tab labels.
      await _pumpBar(
        tester,
        currentIndex: 0,
        onTap: (_) {},
        onScan: () {},
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Practice'), findsOneWidget);
    });

    testWidgets('works in light theme too', (tester) async {
      await _pumpBar(
        tester,
        currentIndex: 1,
        onTap: (_) {},
        onScan: () {},
        theme: AppTheme.light,
      );

      expect(find.text('Practice'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
