import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/widgets/feedback/loading_state.dart';
import 'package:matheasy/core/widgets/indicators/matheasy_loader.dart';

void main() {
  // Reads the current opacity of each dot (each dot is wrapped in an Opacity).
  List<double> dotOpacities(WidgetTester tester) => tester
      .widgetList<Opacity>(
        find.descendant(
          of: find.byType(MatheasyLoader),
          matching: find.byType(Opacity),
        ),
      )
      .map((o) => o.opacity)
      .toList();

  testWidgets('MatheasyLoader animates — the dot wave actually moves', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: MatheasyLoader())),
      ),
    );
    await tester.pump();
    final before = dotOpacities(tester).first;
    await tester.pump(const Duration(milliseconds: 350)); // ~quarter cycle
    final after = dotOpacities(tester).first;
    expect(
      (before - after).abs(),
      greaterThan(0.05),
      reason: 'the pulsing wave should change a dot opacity over time',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('MatheasyLoader holds still — but visible — under reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: const Scaffold(body: Center(child: MatheasyLoader())),
          ),
        ),
      ),
    );
    await tester.pump();
    // If the loader still looped, there would be pending frames forever and
    // pumpAndSettle would time out — reaching here proves it is static.
    await tester.pumpAndSettle();
    final opacities = dotOpacities(tester);
    expect(opacities.length, 3);
    // Static, but rendered at a calm-yet-visible opacity — never blanked out.
    expect(opacities, everyElement(closeTo(0.7, 0.001)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('LoadingState shows the animated loader alongside its message', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LoadingState(message: 'Solving…')),
      ),
    );
    await tester.pump();
    expect(find.byType(MatheasyLoader), findsOneWidget);
    expect(find.text('Solving…'), findsOneWidget);
  });
}
