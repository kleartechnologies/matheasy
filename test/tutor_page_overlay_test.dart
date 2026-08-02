// Numi pointing at the student's own page.
//
// The visual-teaching layer only earns its place if the thing it outlines is
// the thing it says it is. Every test here defends that: an anchor whose box
// can't be trusted is dropped, an action whose target nobody located is
// dropped, and the overlay never draws coordinates a model proposed. A wrongly
// placed highlight is a hallucination with a highlighter — it tells a student
// their own handwriting says something it doesn't.
//
// The rest covers what makes it usable: the photo travels once while the
// anchors travel every turn, motion respects Reduce Motion, contrast respects
// the high-contrast flag, and a screen reader is told where to look in words.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matheasy/core/theme/app_colors.dart';
import 'package:matheasy/core/theme/app_semantic_colors.dart';
import 'package:matheasy/core/theme/math_semantics.dart';
import 'package:matheasy/features/result/domain/result_models.dart';
import 'package:matheasy/features/scan/application/functions_scanner_service.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_anchor.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/tutor/application/functions_tutor_service.dart';
import 'package:matheasy/features/tutor/domain/tutor_context_builder.dart';
import 'package:matheasy/features/tutor/domain/tutor_models.dart';
import 'package:matheasy/features/tutor/presentation/widgets/tutor_page_overlay.dart';

/// A valid 1x1 PNG — enough for `instantiateImageCodec` to produce a real
/// `ui.Image`, which is what the painter needs.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

Map<String, dynamic> _anchorJson({
  String id = 'angle_B',
  String type = 'angle',
  String label = '28°',
  String role = 'known',
  String? vertex,
  Map<String, dynamic>? box,
}) =>
    {
      'id': id,
      'type': type,
      'label': label,
      'role': role,
      'vertex': ?vertex,
      'box': box ?? {'x': 0.2, 'y': 0.3, 'w': 0.1, 'h': 0.08},
      'confidence': 0.9,
    };

ScanAnchor _anchor({
  String id = 'angle_B',
  MathRole role = MathRole.known,
  Rect? rect,
}) =>
    ScanAnchor(
      id: id,
      type: 'angle',
      label: '28°',
      role: role,
      rect: rect ?? const Rect.fromLTWH(0.2, 0.3, 0.1, 0.08),
    );

DetectedEquation _equation({List<ScanAnchor> anchors = const []}) =>
    DetectedEquation(
      latex: r'x + 28 = 90',
      confidence: 0.9,
      source: ScanSource.camera,
      kind: EquationKind.geometry,
      imageBytes: _png,
      anchors: anchors,
    );

Widget _host(Widget child, {bool reduceMotion = false, bool highContrast = false}) {
  return MaterialApp(
    // The semantic palette without `AppTheme.light`'s Google-fonts text theme:
    // decoding the page needs `runAsync`, and under it a live font fetch would
    // throw. The overlay draws no text, so nothing is lost.
    theme: ThemeData(
      extensions: const <ThemeExtension<dynamic>>[AppSemanticColors.light],
    ),
    home: MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduceMotion,
        highContrast: highContrast,
      ),
      child: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
    ),
  );
}

/// Pump an overlay and wait for the page to actually decode.
///
/// The photo becomes a real `ui.Image` through `instantiateImageCodec`, which
/// resolves on the real event loop — inside a widget test that only happens
/// under [WidgetTester.runAsync]. Without this the overlay is still in its
/// pre-decode `SizedBox.shrink()` and every assertion below would be testing
/// an empty frame.
Future<void> _pumpOverlay(
  WidgetTester tester, {
  required List<TutorAction> actions,
  List<ScanAnchor>? anchors,
  bool reduceMotion = false,
  bool highContrast = false,
  Widget Function(Widget child)? wrap,
}) async {
  final overlay = TutorPageOverlay(
    imageBytes: _png,
    anchors: anchors ?? [_anchor()],
    actions: actions,
  );
  await tester.runAsync(() async {
    await tester.pumpWidget(
      _host(
        wrap == null ? overlay : wrap(overlay),
        reduceMotion: reduceMotion,
        highContrast: highContrast,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// The one painter in the tree that is actually drawing the page.
TutorPageOverlayPainter _painterOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((w) => w.painter)
    .whereType<TutorPageOverlayPainter>()
    .single;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('ScanAnchor — a box is only kept if it can be drawn honestly', () {
    test('parses a well-formed anchor into a normalized rect', () {
      final anchors = ScanAnchor.listFromJson([_anchorJson(vertex: 'B')]);
      expect(anchors, hasLength(1));
      final anchor = anchors.single;
      expect(anchor.id, 'angle_B');
      expect(anchor.role, MathRole.known);
      // Right/bottom are recomputed as x+w, so compare within float noise.
      expect(anchor.rect.left, closeTo(0.2, 1e-9));
      expect(anchor.rect.top, closeTo(0.3, 1e-9));
      expect(anchor.rect.right, closeTo(0.3, 1e-9));
      expect(anchor.rect.bottom, closeTo(0.38, 1e-9));
    });

    test('drops a box given in pixels rather than fractions of the frame', () {
      // The most likely mistake and the most dangerous: 412 would put the
      // outline nowhere on the page at all.
      final anchors = ScanAnchor.listFromJson([
        _anchorJson(box: {'x': 412, 'y': 233, 'w': 60, 'h': 24}),
      ]);
      expect(anchors, isEmpty);
    });

    test('drops NaN, missing and too-small boxes', () {
      expect(
        ScanAnchor.listFromJson([
          _anchorJson(box: {'x': double.nan, 'y': 0.1, 'w': 0.1, 'h': 0.1}),
          _anchorJson(id: 'b', box: {'x': 0.1, 'y': 0.1, 'w': 0.1}),
          _anchorJson(id: 'c', box: {'x': 0.5, 'y': 0.5, 'w': 0.0001, 'h': 0.2}),
        ]),
        isEmpty,
      );
    });

    test('drops an anchor with no id — there would be nothing to point at', () {
      expect(ScanAnchor.listFromJson([_anchorJson(id: '  ')]), isEmpty);
    });

    test('keeps the first of two anchors sharing an id', () {
      final anchors = ScanAnchor.listFromJson([
        _anchorJson(),
        _anchorJson(label: '31°'),
      ]);
      expect(anchors, hasLength(1));
      expect(anchors.single.label, '28°');
    });

    test('degrades an unknown role to aside rather than inventing meaning', () {
      final anchors = ScanAnchor.listFromJson([_anchorJson(role: 'chartreuse')]);
      expect(anchors.single.role, MathRole.aside);
    });

    test('survives a round trip through JSON', () {
      // Binary-exact fractions, so the assertion is about the round trip and
      // not about float noise in `x + w`.
      final anchor = _anchor(rect: const Rect.fromLTWH(0.25, 0.5, 0.125, 0.0625));
      expect(ScanAnchor.fromJson(anchor.toJson()), anchor);
    });

    test('scales into pixels for a laid-out image', () {
      final rect = _anchor().toPixels(200, 100);
      expect(rect.left, closeTo(40, 0.001));
      expect(rect.top, closeTo(30, 0.001));
      expect(rect.width, closeTo(20, 0.001));
    });

    test('reads aloud by place and role, not by value alone', () {
      final anchor = ScanAnchor.listFromJson([_anchorJson(vertex: 'B')]).single;
      expect(anchor.semanticLabel, contains('vertex B'));
      expect(anchor.semanticLabel, contains('angle'));
    });
  });

  group('the scan carries the anchors to the client', () {
    test('maps the anchors array off the recognizeEquation payload', () async {
      final service = FunctionsScannerService((name, data) async => {
            'latex': r'x + 28 = 90',
            'confidence': 0.94,
            'topic': 'geometry',
            'anchors': [_anchorJson(), _anchorJson(id: 'unknown_x')],
          });
      final result = await service.recognize(
        ScanSource.camera,
        imageBytes: _png,
      );
      expect(result.anchors.map((a) => a.id), ['angle_B', 'unknown_x']);
    });

    test('an older backend without anchors simply yields no overlay', () async {
      final service = FunctionsScannerService((name, data) async => {
            'latex': r'2x = 8',
            'confidence': 0.9,
          });
      final result = await service.recognize(ScanSource.camera, imageBytes: _png);
      expect(result.anchors, isEmpty);
    });

    test('anchors are transient — history never carries the coordinates', () {
      final json = _equation(anchors: [_anchor()]).toJson();
      expect(json.containsKey('anchors'), isFalse);
      expect(DetectedEquation.fromJson(json).anchors, isEmpty);
    });

    test('an edit drops them: a corrected misread invalidates every box', () {
      final edited = _equation(anchors: [_anchor()]).copyWith(latex: '2x = 10');
      expect(edited.anchors, isEmpty);
    });
  });

  group('what Numi is handed, and how often', () {
    test('the context builder carries the anchors alongside the photo', () {
      final context = TutorContextBuilder.fromResult(
        _result(anchors: [_anchor(), _anchor(id: 'unknown_x')]),
      );
      expect(context.anchors.map((a) => a.id), ['angle_B', 'unknown_x']);
      expect(context.scanImageBytes, isNotNull);
    });

    test('the anchors ride on every turn — the photo does not', () {
      final context = TutorLaunchContext(
        problem: TutorContextBuilder.fromResult(_result(anchors: [_anchor()])),
      );
      // Turn two and beyond: no pixels on the wire, but Numi can still point.
      final later = TutorRequestMapper.context(context, includeImage: false);
      expect(later.containsKey('imageBase64'), isFalse);
      final problem = later['problem'] as Map<String, dynamic>;
      expect(problem['anchors'], hasLength(1));
      expect((problem['anchors'] as List).first, containsPair('id', 'angle_B'));

      // The opening turn carries both.
      final opening = TutorRequestMapper.context(context);
      expect(opening.containsKey('imageBase64'), isTrue);
      expect((opening['problem'] as Map)['anchors'], hasLength(1));
    });
  });

  group('TutorReplyMapper — the gestures that come back', () {
    test('maps a verified action, colour and all', () {
      final actions = TutorReplyMapper.actions([
        {'type': 'circle', 'target': 'angle_B', 'role': 'known'},
      ]);
      expect(actions.single.type, TutorActionType.circle);
      expect(actions.single.target, 'angle_B');
      expect(actions.single.role, MathRole.known);
    });

    test('drops a gesture this build cannot draw', () {
      // A newer server is not a licence to guess at a new animation.
      expect(
        TutorReplyMapper.actions([
          {'type': 'explode', 'target': 'angle_B'},
        ]),
        isEmpty,
      );
    });

    test('drops an action with no target at all', () {
      expect(
        TutorReplyMapper.actions([
          {'type': 'circle'},
          {'type': 'circle', 'target': '   '},
          'circle angle_B',
        ]),
        isEmpty,
      );
    });

    test('dedupes identical gestures', () {
      final actions = TutorReplyMapper.actions([
        {'type': 'pulse', 'target': 'unknown_x'},
        {'type': 'pulse', 'target': 'unknown_x'},
      ]);
      expect(actions, hasLength(1));
    });

    test('a reply with no actions is an ordinary reply, not an error', () {
      final response = TutorReplyMapper.toResponse({'reply': 'Have a look.'});
      expect(response.actions, isEmpty);
      expect(response.certainty, isNull);
    });

    test('reads the verification state the server echoed', () {
      expect(
        TutorReplyMapper.toResponse({
          'reply': 'x',
          'verification': 'OCR_LOW_CONFIDENCE',
        }).certainty,
        TutorCertainty.ocrLowConfidence,
      );
      expect(TutorCertainty.parse('PASS'), TutorCertainty.pass);
      // A state this build doesn't know must not become a claim of certainty.
      expect(TutorCertainty.parse('PROBABLY_FINE'), isNull);
    });

    test('only the doubtful states ask for the student\'s attention', () {
      expect(TutorCertainty.pass.needsAttention, isFalse);
      expect(TutorCertainty.highConfidence.needsAttention, isFalse);
      expect(TutorCertainty.lowConfidence.needsAttention, isFalse);
      expect(TutorCertainty.ocrLowConfidence.needsAttention, isTrue);
      expect(TutorCertainty.verifierDisagreement.needsAttention, isTrue);
    });
  });

  group('TutorPageOverlay.resolve — the gate on what may be drawn', () {
    test('matches an action to the anchor it names', () {
      final resolved = TutorPageOverlay.resolve(
        const [TutorAction(type: TutorActionType.circle, target: 'angle_B')],
        [_anchor()],
      );
      expect(resolved.single.anchor.id, 'angle_B');
      expect(resolved.single.type, TutorActionType.circle);
    });

    test('DROPS a target nobody located — the rule the whole layer rests on', () {
      final resolved = TutorPageOverlay.resolve(
        const [TutorAction(type: TutorActionType.circle, target: 'angle_Z')],
        [_anchor()],
      );
      expect(resolved, isEmpty);
    });

    test('draws nothing when the page has no anchors', () {
      expect(
        TutorPageOverlay.resolve(
          const [TutorAction(type: TutorActionType.glow, target: 'angle_B')],
          const [],
        ),
        isEmpty,
      );
    });
  });

  group('TutorScannedPage', () {
    test('needs both a photo and somewhere on it to point', () {
      expect(TutorScannedPage.from(null), isNull);
      // A typed problem: no photo.
      expect(
        TutorScannedPage.from(
          const TutorLaunchContext(
            problem: TutorProblemContext(questionLatex: '2x=8'),
          ),
        ),
        isNull,
      );
      // A photo the reader placed nothing on: nothing to point at.
      expect(
        TutorScannedPage.from(
          TutorLaunchContext(
            problem: TutorContextBuilder.fromResult(_result()),
          ),
        ),
        isNull,
      );
      expect(
        TutorScannedPage.from(
          TutorLaunchContext(
            problem: TutorContextBuilder.fromResult(_result(anchors: [_anchor()])),
          ),
        ),
        isNotNull,
      );
    });
  });

  group('the overlay on screen', () {
    testWidgets('draws the student\'s own photo with the gesture over it',
        (tester) async {
      await _pumpOverlay(
        tester,
        actions: const [
          TutorAction(type: TutorActionType.circle, target: 'angle_B'),
        ],
      );
      expect(_painterOf(tester).gestures, hasLength(1));
      // The photo is drawn by the painter itself — there is no Image widget and
      // no regenerated picture anywhere in the tree.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('tells a screen reader WHERE to look, in words', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpOverlay(
        tester,
        anchors: ScanAnchor.listFromJson([_anchorJson(vertex: 'B')]),
        actions: const [
          TutorAction(type: TutorActionType.highlight, target: 'angle_B'),
        ],
      );
      expect(
        find.bySemanticsLabel(RegExp('pointing at.*vertex B')),
        findsOneWidget,
        reason: 'a VoiceOver user is taught the same thing, by place',
      );
      handle.dispose();
    });

    testWidgets('shows nothing at all when there is nowhere to point',
        (tester) async {
      await _pumpOverlay(
        tester,
        // An id the app never derived. Nothing is drawn over the page.
        actions: const [
          TutorAction(type: TutorActionType.circle, target: 'ghost'),
        ],
      );
      expect(_painterOf(tester).gestures, isEmpty);
    });

    testWidgets('Reduce Motion parks the gesture fully drawn instead of looping',
        (tester) async {
      await _pumpOverlay(
        tester,
        actions: const [
          TutorAction(type: TutorActionType.pulse, target: 'angle_B'),
        ],
        reduceMotion: true,
      );
      final painter = _painterOf(tester);
      // Reduce Motion means no MOVEMENT, not no information: the gesture is
      // shown complete and at rest.
      expect(painter.progress.value, 1.0);
      expect(painter.gestures, hasLength(1));
      // And the frame can settle, which a repeating controller would never
      // allow.
      await tester.pumpAndSettle();
    });

    testWidgets('high contrast thickens the stroke it draws with',
        (tester) async {
      await _pumpOverlay(
        tester,
        actions: const [
          TutorAction(type: TutorActionType.underline, target: 'angle_B'),
        ],
        reduceMotion: true,
      );
      final normal = _painterOf(tester);
      expect(normal.highContrast, isFalse);

      await _pumpOverlay(
        tester,
        actions: const [
          TutorAction(type: TutorActionType.underline, target: 'angle_B'),
        ],
        reduceMotion: true,
        highContrast: true,
      );
      final high = _painterOf(tester);
      expect(high.highContrast, isTrue);
      // A 2px hairline over pencil on white paper is exactly what a low-vision
      // learner cannot see.
      expect(high.strokeWidth, greaterThan(normal.strokeWidth));
    });

    testWidgets('paints every gesture type without throwing', (tester) async {
      // The renderer is the one place where a missing case would show up as a
      // blank overlay rather than an exception, so every type gets a frame —
      // at both ends of the cycle, since some gestures only draw late in it.
      for (final type in TutorActionType.values) {
        await _pumpOverlay(
          tester,
          actions: [TutorAction(type: type, target: 'angle_B')],
          reduceMotion: true,
        );
        expect(_painterOf(tester).gestures, hasLength(1));
        expect(tester.takeException(), isNull, reason: '${type.name} threw');
      }
    });

    testWidgets('a whole cycle of motion costs no rebuilds', (tester) async {
      // 60fps is a paint-loop property: the controller drives the painter
      // directly (`repaint:`), so a running gesture must never rebuild or
      // re-layout the widget tree under a scrolling chat.
      var builds = 0;
      await _pumpOverlay(
        tester,
        actions: const [
          TutorAction(type: TutorActionType.glow, target: 'angle_B'),
        ],
        wrap: (child) => Builder(
          builder: (context) {
            builds++;
            return child;
          },
        ),
      );
      final atStart = builds;
      // A full 2.6s cycle, one frame at a time.
      for (var i = 0; i < 163; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(builds, atStart, reason: 'animation must be paint-only');
      expect(_painterOf(tester).progress.isAnimating, isTrue);
    });
  });

  group('the teaching colours stay a vocabulary', () {
    test('the three new roles have their own hues in both themes', () {
      const added = [MathRole.hint, MathRole.concept, MathRole.memory];
      for (final isDark in [false, true]) {
        final scheme = isDark ? AppSemanticColors.dark : AppSemanticColors.light;
        for (final role in added) {
          final colour = role.color(scheme, isDark: isDark);
          for (final other in MathRole.values) {
            if (other == role) continue;
            expect(
              colour.toARGB32(),
              isNot(other.color(scheme, isDark: isDark).toARGB32()),
              reason: '${role.name} collides with ${other.name}',
            );
          }
        }
      }
    });

    test('memory is never gold on a light surface — gold is 1.63:1 there', () {
      expect(
        MathRole.memory.color(AppSemanticColors.light, isDark: false),
        isNot(AppColors.gold),
      );
    });
  });
}

ResultData _result({List<ScanAnchor> anchors = const []}) => ResultData(
      equation: _equation(anchors: anchors),
      type: ResultType.geometry,
      difficulty: Difficulty.easy,
      answerLatex: 'x = 62',
      verifyText: 'Substituted back into the original equation.',
      steps: const [],
      explanations: const [],
      methods: const [],
      practice: const [],
      tutorIntro: '',
    );
