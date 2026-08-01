import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/animations/motion_aware_size.dart';

/// A box whose height flips when [tall] does — enough to make the size
/// animation restart, which is where the zero-duration bug bites.
Widget _host({required Duration duration, required bool tall}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MotionAwareSize(
          duration: duration,
          alignment: Alignment.topCenter,
          child: SizedBox(width: 100, height: tall ? 200.0 : 40.0),
        ),
      ),
    ),
  );
}

void main() {
  group('MotionAwareSize', () {
    testWidgets('animates the size change when motion is on', (tester) async {
      await tester.pumpWidget(
        _host(duration: const Duration(milliseconds: 300), tall: false),
      );
      expect(find.byType(AnimatedSize), findsOneWidget);
    });

    testWidgets('drops the wrapper entirely when motion is off',
        (tester) async {
      await tester.pumpWidget(_host(duration: Duration.zero, tall: false));
      // Not "an AnimatedSize with a 0 ms duration" — no AnimatedSize at all.
      expect(find.byType(AnimatedSize), findsNothing);
      expect(tester.getSize(find.byType(SizedBox).first).height, 40);
    });

    testWidgets('a size change under reduced motion does not re-dirty layout',
        (tester) async {
      // The regression: AnimatedSize starts its controller inside
      // performLayout, and a zero-duration forward() completes synchronously,
      // so the completion listener markNeedsLayout's the render object still
      // being laid out — "A RenderAnimatedSize was mutated in its own
      // performLayout implementation". Every learner with Reduce Motion on hit
      // it the moment a step expanded.
      await tester.pumpWidget(_host(duration: Duration.zero, tall: false));
      await tester.pumpWidget(_host(duration: Duration.zero, tall: true));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(SizedBox).first).height, 200);
    });
  });
}
