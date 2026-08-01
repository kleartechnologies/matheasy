import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/brand/brand.dart';
import 'package:matheasy/core/theme/app_colors.dart';

/// Numi is the official AI identity, and the design export is its source of
/// truth. These tests pin the numbers a well-meaning tweak would quietly move:
/// the star's geometry, the 24→256 ramp, and what each of the four official
/// states actually does.
void main() {
  group('the four-point star', () {
    // The export clips the star with
    //   polygon(50% 0%, 60.6% 39.4%, 100% 50%, 60.6% 60.6%,
    //           50% 100%, 39.4% 60.6%, 0% 50%, 39.4% 39.4%)
    // — eight vertices, in percentages of the star's own box.
    const List<Offset> clipPath = <Offset>[
      Offset(0.500, 0.000),
      Offset(0.606, 0.394),
      Offset(1.000, 0.500),
      Offset(0.606, 0.606),
      Offset(0.500, 1.000),
      Offset(0.394, 0.606),
      Offset(0.000, 0.500),
      Offset(0.394, 0.394),
    ];

    test('reproduces the export clip-path, vertex for vertex', () {
      const double size = 100;
      final path = numiStarPath(center: const Offset(50, 50), size: size);
      expect(path.computeMetrics().length, 1, reason: 'one closed contour');
      for (final vertex in clipPath) {
        expect(
          _nearContour(path, Offset(vertex.dx * size, vertex.dy * size)),
          isTrue,
          reason: 'vertex $vertex must lie on the star outline',
        );
      }
    });

    test('is exactly as wide as it is tall, and fills its box', () {
      final bounds = numiStarPath(center: Offset.zero, size: 80).getBounds();
      expect(bounds.width, closeTo(80, 0.001));
      expect(bounds.height, closeTo(80, 0.001));
      expect(bounds.center.dx, closeTo(0, 0.001));
      expect(bounds.center.dy, closeTo(0, 0.001));
    });

    test("has its axis locked upright — a point at 12 o'clock", () {
      // §11: "never rotate the star". The four outer points sit exactly on the
      // vertical and horizontal centrelines.
      final path = numiStarPath(center: const Offset(50, 50), size: 100);
      expect(path.getBounds().top, closeTo(0, 0.001));
      expect(_nearContour(path, const Offset(50, 0)), isTrue);
      expect(_nearContour(path, const Offset(50, 100)), isTrue);
      expect(_nearContour(path, const Offset(0, 50)), isTrue);
      expect(_nearContour(path, const Offset(100, 50)), isTrue);
    });

    test('inner ratio is 0.30 of the outer radius', () {
      expect(NumiSpec.starInnerRatio, 0.30);
      // …which is what puts the waist at 39.4% / 60.6%.
      const waist = 0.5 - NumiSpec.starInnerRatio * 0.5 / _sqrt2;
      expect(waist, closeTo(0.394, 0.0006));
    });

    test('scales with the orb — geometry is a fraction of D, never pixels', () {
      for (final d in <double>[24, 40, 96, 256]) {
        final star = NumiSpec.starRatioFor(d) * d;
        final bounds = numiStarPath(
          center: Offset(d / 2, d * NumiSpec.starCenter.dy),
          size: star,
        ).getBounds();
        expect(bounds.width, closeTo(star, 0.001));
      }
    });
  });

  group('the scale ramp (§07)', () {
    test('star ratio: 256/128/64 → .26, 48 → .28, 32 → .30, 24 → .32', () {
      expect(NumiSpec.starRatioFor(256), 0.26);
      expect(NumiSpec.starRatioFor(128), 0.26);
      expect(NumiSpec.starRatioFor(64), 0.26);
      expect(NumiSpec.starRatioFor(48), 0.28);
      expect(NumiSpec.starRatioFor(32), 0.30);
      expect(NumiSpec.starRatioFor(24), 0.32);
    });

    test('the glow pulls back below 48 px, so a small orb stays a shape', () {
      expect(NumiSpec.glowRampFor(256), 1.0);
      expect(NumiSpec.glowRampFor(48), 1.0);
      expect(NumiSpec.glowRampFor(32), 0.70);
      expect(NumiSpec.glowRampFor(24), 0.55);
    });

    test('the star grows as the orb shrinks — never the other way round', () {
      var previous = 0.0;
      for (final d in <double>[256, 128, 64, 48, 32, 24]) {
        final ratio = NumiSpec.starRatioFor(d);
        expect(ratio, greaterThanOrEqualTo(previous));
        previous = ratio;
      }
    });
  });

  group('the palette (§04)', () {
    test('is the locked five, and nothing else is invented', () {
      expect(NumiSpec.coreGreen, const Color(0xFF05AC60));
      expect(NumiSpec.highlight, const Color(0xFF8DF5BC));
      expect(NumiSpec.shadow, const Color(0xFF023B21));
      expect(NumiSpec.shadowOnBrand, const Color(0xFF012D19));
      expect(NumiSpec.glow, const Color(0xFF3ADE8C));
    });

    test("Numi's green is the app's emerald identity, not a new brand hue", () {
      // Not bit-identical — each keeps the value its own source of truth
      // states — but the two must stay the same colour to the eye.
      const numi = NumiSpec.coreGreen;
      const app = AppColors.primary;
      expect(
        (numi.r - app.r).abs() +
            (numi.g - app.g).abs() +
            (numi.b - app.b).abs(),
        lessThan(0.02),
      );
    });

    test('the body gradient runs light → dark, seven stops, in order', () {
      expect(NumiSpec.bodyColors, hasLength(NumiSpec.bodyStops.length));
      expect(NumiSpec.bodyStops.first, 0.0);
      expect(NumiSpec.bodyStops.last, 1.0);
      for (var i = 1; i < NumiSpec.bodyStops.length; i++) {
        expect(NumiSpec.bodyStops[i], greaterThan(NumiSpec.bodyStops[i - 1]));
        expect(
          NumiSpec.bodyColors[i].computeLuminance(),
          lessThan(NumiSpec.bodyColors[i - 1].computeLuminance()),
          reason: 'the sphere must darken away from its light source',
        );
      }
      // The one green sits at the middle of the ramp.
      expect(NumiSpec.bodyColors[3], NumiSpec.coreGreen);
    });

    test('the light source is up and to the left — 10:30 (§02)', () {
      expect(NumiSpec.bodyCenter.dx, lessThan(0.5));
      expect(NumiSpec.bodyCenter.dy, lessThan(0.5));
      // …and the specular hot spot agrees with it.
      expect(NumiSpec.specularCenter.dx, lessThan(0.5));
      expect(NumiSpec.specularCenter.dy, lessThan(0.5));
    });

    test('a brand-green surface deepens the terminator, and kills the glow',
        () {
      expect(NumiSurface.brandGreen.shadowEdge, NumiSpec.shadowOnBrand);
      expect(NumiSurface.brandGreen.glowScale, 0);
      expect(NumiSurface.light.glowScale, 0.5);
      expect(NumiSurface.light.rimOpacity, 0.6);
      expect(NumiSurface.dark.rimOpacity, 1.0);
    });
  });

  group('the four official states (§05)', () {
    test('are exactly four — Numi has no other mode', () {
      expect(NumiState.values, hasLength(4));
    });

    test('idle is still: no ripple, no sparkle, the slowest drift', () {
      final frame = NumiFrame.at(time: 0, state: NumiState.idle);
      expect(frame.ripples, isEmpty);
      expect(frame.sparkles, isEmpty);
      expect(
        NumiStateSpec.idle.coreDuration,
        greaterThan(NumiStateSpec.thinking.coreDuration),
      );
    });

    test('listening leans in through light, not movement', () {
      // "Numi leans in through light only — never through movement."
      expect(
        NumiStateSpec.listening.glowScale,
        greaterThan(NumiStateSpec.idle.glowScale),
      );
      expect(
        NumiStateSpec.listening.scalePeak,
        lessThan(NumiStateSpec.idle.scalePeak),
      );
      expect(
        NumiFrame.at(time: 0.2, state: NumiState.listening).ripples,
        hasLength(2),
      );
    });

    test('thinking is the signature state: three staggered ripples', () {
      final frame = NumiFrame.at(time: 0.2, state: NumiState.thinking);
      expect(frame.ripples, hasLength(3));
      // Staggered, so no two rings sit on top of each other.
      expect(frame.ripples.map((r) => r.scale).toSet(), hasLength(3));
      // Each successive ring is fainter than the one before it.
      expect(
        NumiStateSpec.thinking.rings.map((r) => r.opacity).toList(),
        <double>[0.4, 0.28, 0.18],
      );
    });

    test('the star never moves — only the light around it does', () {
      // §05: "The star stays perfectly still — the light moves, never the
      // symbol." The star's position is a constant of the spec; only the core
      // drifts, and it is the only thing in the frame that can.
      final a = NumiFrame.at(time: 0.0, state: NumiState.thinking);
      final b = NumiFrame.at(time: 1.7, state: NumiState.thinking);
      expect(a.coreOffset, isNot(b.coreOffset));
      expect(NumiSpec.starCenter, const Offset(0.5, 0.47));
    });

    test('responding blooms once, then settles back to idle', () {
      const state = NumiState.responding;
      final bloom = NumiFrame.at(time: 0.3, state: state, stateAge: 0.3);
      expect(bloom.ripples, isNotEmpty);
      expect(bloom.sparkles, isNotEmpty);

      // 600 ms bloom + 900 ms settle; after that it is idle in every respect.
      final settled = NumiFrame.at(time: 4, state: state, stateAge: 4);
      final idle = NumiFrame.at(time: 4, state: NumiState.idle);
      expect(settled.ripples, isEmpty, reason: 'no fireworks, no celebration');
      expect(settled.sparkles, isEmpty);
      expect(settled.glowOpacity, closeTo(idle.glowOpacity, 1e-9));
      expect(settled.scale, closeTo(idle.scale, 1e-9));
    });

    test('the glow ranks idle < thinking < listening < responding', () {
      double glow(NumiState s) => NumiStateSpec.of(s).glowScale;
      expect(glow(NumiState.idle), lessThan(glow(NumiState.thinking)));
      expect(glow(NumiState.thinking), lessThan(glow(NumiState.listening)));
      expect(glow(NumiState.listening), lessThan(glow(NumiState.responding)));
    });
  });

  group('motion', () {
    test('breathes on a 6.5s loop: rest at 0, peak at half, rest at the end',
        () {
      const period = 6.5;
      final start = NumiFrame.at(time: 0, state: NumiState.idle);
      final mid = NumiFrame.at(time: period / 2, state: NumiState.idle);
      final end = NumiFrame.at(time: period, state: NumiState.idle);

      expect(start.scale, closeTo(1.0, 1e-6));
      expect(mid.scale, closeTo(NumiStateSpec.idle.scalePeak, 1e-6));
      expect(end.scale, closeTo(1.0, 1e-6));

      // The float goes up, never down.
      expect(start.floatY, closeTo(0, 1e-6));
      expect(mid.floatY, lessThan(0));
    });

    test('is so small it is felt rather than seen', () {
      // §05 idle: "patiently waiting, not idling".
      expect(NumiStateSpec.idle.scalePeak - 1, lessThan(0.02));
      expect(NumiSpec.breatheFloat.abs(), lessThan(0.02));
    });

    test('the internal light drifts between the two keyframed positions', () {
      for (final t in <double>[0, 0.9, 1.8, 2.7, 3.6, 5.4]) {
        final frame = NumiFrame.at(time: t, state: NumiState.thinking);
        expect(frame.coreOffset.dx, inInclusiveRange(-0.02, 0.04));
        expect(frame.coreOffset.dy, inInclusiveRange(-0.04, 0.01));
        expect(frame.coreScale, inInclusiveRange(1.0, 1.09));
        expect(frame.coreOpacity, inInclusiveRange(0.82, 1.0));
      }
    });

    test('the ambient field breathes with the orb and stays in its band', () {
      for (final t in <double>[0, 1.3, 3.25, 4.9, 6.5]) {
        final frame = NumiFrame.at(time: t, state: NumiState.idle);
        expect(
          frame.glowOpacity,
          inInclusiveRange(
            NumiSpec.glowOpacityRest - 1e-9,
            NumiSpec.glowOpacityPeak + 1e-9,
          ),
        );
        expect(
          frame.glowSpread,
          inInclusiveRange(1.0, NumiSpec.glowSpreadPeak),
        );
      }
    });

    test('a ripple expands and fades to nothing, never the reverse', () {
      NumiRipple ringAt(double t) =>
          NumiFrame.at(time: t, state: NumiState.thinking).ripples.first;
      final early = ringAt(0.01);
      final late = ringAt(3.0);
      expect(late.scale, greaterThan(early.scale));
      expect(late.opacity, lessThan(early.opacity));
      expect(ringAt(3.399).opacity, lessThan(0.02));
    });

    test('the still frame holds the resting keyframe, with no motion in it',
        () {
      final still = NumiFrame.still();
      expect(still.scale, 1.0);
      expect(still.floatY, 0.0);
      expect(still.coreOffset, NumiSpec.coreDriftRest);
      expect(still.ripples, isEmpty);
      expect(still.sparkles, isEmpty);
      expect(still.glowSpread, 1.0);
    });
  });

  group('NumiAvatar', () {
    testWidgets('renders at every size from 24 to 256', (tester) async {
      for (final size in <double>[24, 32, 40, 48, 64, 96, 128, 256]) {
        await tester.pumpWidget(_host(NumiAvatar(size: size)));
        expect(tester.getSize(find.byType(NumiAvatar)), Size.square(size));
        expect(_painterOf(tester).starRatio, NumiSpec.starRatioFor(size));
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    testWidgets('announces itself as Numi', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const NumiAvatar(size: 40)));
      expect(find.bySemanticsLabel('Numi'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('animates by default and holds still when asked not to',
        (tester) async {
      await tester.pumpWidget(_host(const NumiAvatar(size: 120)));
      await tester.pump(const Duration(milliseconds: 16));
      final moving = _frameOf(tester);
      await tester.pump(const Duration(milliseconds: 900));
      expect(_frameOf(tester), isNot(moving));

      await tester.pumpWidget(
        _host(const NumiAvatar(size: 120, animate: false)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final still = _frameOf(tester);
      await tester.pump(const Duration(milliseconds: 900));
      expect(_frameOf(tester), still);
    });

    testWidgets('respects the platform reduced-motion setting', (tester) async {
      await tester.pumpWidget(
        _host(
          const NumiAvatar(size: 120, state: NumiState.thinking),
          disableAnimations: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final frame = _frameOf(tester);
      expect(frame.scale, 1.0);
      expect(frame.ripples, isEmpty);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(_frameOf(tester), frame);
    });

    testWidgets('still reads as thinking with motion off — through light',
        (tester) async {
      Future<double> glowFor(NumiState state) async {
        await tester.pumpWidget(
          _host(NumiAvatar(size: 120, state: state), disableAnimations: true),
        );
        await tester.pump(const Duration(milliseconds: 16));
        return _frameOf(tester).glowOpacity;
      }

      expect(
        await glowFor(NumiState.thinking),
        greaterThan(await glowFor(NumiState.idle)),
      );
    });

    testWidgets('picks its environment from the theme, and can be overridden',
        (tester) async {
      await tester.pumpWidget(_host(const NumiAvatar(size: 120)));
      expect(_painterOf(tester).surface, NumiSurface.light);

      await tester.pumpWidget(
        _host(const NumiAvatar(size: 120), brightness: Brightness.dark),
      );
      expect(_painterOf(tester).surface, NumiSurface.dark);

      await tester.pumpWidget(
        _host(
          const NumiAvatar(size: 120, surface: NumiSurface.brandGreen),
          brightness: Brightness.dark,
        ),
      );
      expect(_painterOf(tester).surface, NumiSurface.brandGreen);
    });

    testWidgets('restarts the responding one-shot each time it is entered',
        (tester) async {
      await tester.pumpWidget(_host(const NumiAvatar(size: 120)));
      await tester.pump(const Duration(seconds: 5));

      await tester.pumpWidget(
        _host(const NumiAvatar(size: 120, state: NumiState.responding)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // The bloom must be happening *now*, not five seconds ago.
      expect(_frameOf(tester).sparkles, isNotEmpty);
    });

    testWidgets('never leaves a ticker running after it is gone',
        (tester) async {
      await tester.pumpWidget(_host(const NumiAvatar(size: 120)));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(_host(const SizedBox.shrink()));
      // A leaked ticker fails the test on teardown.
      await tester.pump(const Duration(milliseconds: 16));
    });
  });
}

// ── helpers ─────────────────────────────────────────────────────────────
const double _sqrt2 = 1.4142135623730951;

Widget _host(
  Widget child, {
  bool disableAnimations = false,
  Brightness brightness = Brightness.light,
}) {
  return MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: ThemeData(brightness: brightness),
        child: Center(child: child),
      ),
    ),
  );
}

NumiOrbPainter _painterOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(
    find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is NumiOrbPainter,
    ),
  );
  return paint.painter! as NumiOrbPainter;
}

NumiFrame _frameOf(WidgetTester tester) => _painterOf(tester).frame;

/// Is [point] on (or within [tolerance] of) the path's outline?
bool _nearContour(Path path, Offset point, {double tolerance = 0.5}) {
  for (final metric in path.computeMetrics()) {
    for (var d = 0.0; d <= metric.length; d += 0.25) {
      final position = metric.getTangentForOffset(d)?.position;
      if (position != null && (position - point).distance <= tolerance) {
        return true;
      }
    }
  }
  return false;
}
