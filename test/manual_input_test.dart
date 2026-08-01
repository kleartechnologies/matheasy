import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/scan/application/math_field_controller.dart';
import 'package:matheasy/features/scan/application/scanner_service.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/math_input.dart';
import 'package:matheasy/features/scan/domain/math_node.dart';
import 'package:matheasy/features/scan/domain/math_templates.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/scan/presentation/manual_input_screen.dart';
import 'package:matheasy/features/scan/presentation/widgets/math_field.dart';
import 'package:matheasy/features/scan/presentation/widgets/math_key_catalogue.dart';
import 'package:matheasy/features/scan/presentation/widgets/math_keyboard.dart';

void main() {
  group('MathInput.validate', () {
    test('rejects empty / whitespace', () {
      expect(MathInput.validate('   '), isNotNull);
    });
    test('rejects operators-only (no numbers or variables)', () {
      expect(MathInput.validate('+ = ( )'), isNotNull);
    });
    test('rejects unbalanced brackets', () {
      expect(MathInput.validate(r'\frac{3}{4'), isNotNull);
      expect(MathInput.validate('2(x+1'), isNotNull);
    });
    test('accepts a plain equation', () {
      expect(MathInput.validate('2x + 5 = 13'), isNull);
    });
    test('accepts LaTeX with fractions and roots', () {
      expect(MathInput.validate(r'\frac{3}{4} + \sqrt{2}'), isNull);
    });
  });

  group('MathInput.validateExpression (the structured editor rule)', () {
    test('an unfilled dashed box blocks submission', () {
      expect(
        MathInput.validateExpression(r'\frac{2}{}', hasEmptySlot: true),
        MathInput.emptyBoxMessage,
      );
    });
    test('nothing typed still reads as empty, not as an empty box', () {
      expect(
        MathInput.validateExpression('  ', hasEmptySlot: false),
        MathInput.emptyMessage,
      );
    });
    test('a fully filled expression passes', () {
      expect(
        MathInput.validateExpression(r'\frac{2}{3}', hasEmptySlot: false),
        isNull,
      );
    });
  });

  group('MathInput.isBalanced', () {
    test('balanced mixed brackets', () {
      expect(MathInput.isBalanced(r'\sqrt{(x+1)}[2]'), isTrue);
    });
    test('wrong closing order is unbalanced', () {
      expect(MathInput.isBalanced('([)]'), isFalse);
    });
  });

  group('the key catalogue mirrors the reference keyboard', () {
    List<MathKeySpec> allKeys(MathKeyTab tab) => [
          for (final row in tab.rows)
            for (final key in row)
              if (key != null) ...[key, ...key.alternates],
        ];

    final everyKey = [
      for (final tab in MathKeyboard.tabs) ...allKeys(tab),
      ...allKeys(MathKeyboard.letters),
    ];

    String latexOf(MathKeySpec key) =>
        key.atom?.latex ??
        key.template!.toLatex(
          List.filled(key.template!.slotCount, 'a'),
        );

    final inserts = everyKey.map(latexOf).join(' ');

    test('fractions, exponents, roots, parens, variables, trig, calc, logs', () {
      expect(inserts, contains(r'\frac'), reason: 'fractions');
      expect(inserts, contains('^{'), reason: 'exponents');
      expect(inserts, contains(r'\sqrt'), reason: 'square roots');
      expect(inserts, contains('('), reason: 'parentheses');
      expect(inserts, contains('x'), reason: 'variables');
      expect(inserts, contains(r'\sin'), reason: 'trigonometry');
      expect(inserts, contains(r'\int'), reason: 'calculus');
      expect(inserts, contains(r'\log'), reason: 'logarithms');
      expect(inserts, contains(r'\lim'), reason: 'limits');
      expect(inserts, contains(r'\binom'), reason: 'combinatorics');
      expect(inserts, contains('bmatrix'), reason: 'matrices');
    });

    test('four tabs plus the letters page', () {
      expect(MathKeyboard.tabs.length, 4);
      expect(MathKeyboard.letters.rows, isNotEmpty);
    });

    test('every key does something — an atom or a template', () {
      for (final key in everyKey) {
        expect(
          key.atom != null || key.template != null,
          isTrue,
          reason: 'dead key: ${key.label}',
        );
      }
    });

    test('every grid is rectangular so the hairlines line up', () {
      for (final tab in [...MathKeyboard.tabs, MathKeyboard.letters]) {
        for (final row in tab.rows) {
          expect(row.length, tab.columns, reason: tab.id);
        }
      }
    });

    test('labels are unique within a page (they key the cells)', () {
      for (final tab in [...MathKeyboard.tabs, MathKeyboard.letters]) {
        final labels = [
          for (final row in tab.rows)
            for (final key in row)
              if (key != null) key.label,
        ];
        expect(labels.toSet().length, labels.length, reason: tab.id);
      }
    });

    test('a wrapping key always has somewhere to put the operand', () {
      for (final key in everyKey.where((k) => k.wrapPrevious)) {
        expect(key.template, isNotNull, reason: key.label);
        expect(key.template!.slotCount, greaterThan(0), reason: key.label);
      }
    });
  });

  group('MathFieldController builds structured nested LaTeX (§6)', () {
    test('a fraction with an exponent inside → \\frac{x^{2}}{3}', () {
      final c = MathFieldController()
        ..insertTemplate(MathTemplates.frac) // caret → numerator
        ..insertAtom(MathAtom.char('x'))
        ..applyToPrevious(MathTemplates.square); // wraps the x

      // Out of the numerator, into the denominator.
      c
        ..moveRight()
        ..insertAtom(MathAtom.char('3'));

      expect(c.latex, r'\frac{x^{2}}{3}');
      expect(c.hasEmptySlot, isFalse);
    });

    test('a root over an expression → \\sqrt{x+1}', () {
      final c = MathFieldController()..insertTemplate(MathTemplates.sqrt);
      for (final ch in ['x', '+', '1']) {
        c.insertAtom(MathAtom.char(ch));
      }
      expect(c.latex, r'\sqrt{x+1}');
    });

    test('an opened structure reports its empty boxes', () {
      final c = MathFieldController()..insertTemplate(MathTemplates.frac);
      expect(c.hasEmptySlot, isTrue);
      c.insertAtom(MathAtom.char('2'));
      expect(c.hasEmptySlot, isTrue, reason: 'the denominator is still empty');
    });

    test('backspace steps into a filled structure instead of deleting it', () {
      final c = MathFieldController(initialLatex: r'\frac{2}{3}')
        ..placeCursor(const [], 1) // just after the fraction
        ..backspace();
      expect(c.latex, r'\frac{2}{3}', reason: 'nothing deleted yet');
      c.backspace();
      expect(c.latex, r'\frac{2}{}');
    });

    test('pre-filled OCR LaTeX round-trips through the editor', () {
      for (final latex in [
        r'2x+5=13',
        r'\frac{x^{2}}{3}',
        r'\sqrt{x+1}',
      ]) {
        expect(MathFieldController(initialLatex: latex).latex, latex);
      }
    });

    test('a construct the parser rewrites still lands on a fixed point', () {
      // Not every recognized string is re-emitted character for character —
      // `\int_a^b` folds its two scripts into one node. What must hold is that
      // opening the editor a second time changes nothing more, so correcting a
      // scan repeatedly can't drift the problem away from what was scanned.
      for (final latex in [
        r'\int_{0}^{1} x \,dx',
        r'\sum_{i=1}^{n} i',
        r'x_{1}^{2}',
        r'\log_{2}(8)',
        r'\frac{3}{4} + \sqrt{2}',
      ]) {
        final once = MathFieldController(initialLatex: latex).latex;
        expect(MathFieldController(initialLatex: once).latex, once);
      }
    });
  });

  group('the keyboard types into the field', () {
    Future<void> pumpKeyboard(
      WidgetTester tester, {
      double textScale = 1,
    }) async {
      // A phone-sized surface so the full keyboard + field lay out without
      // overflowing the default 800×600 test viewport.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: const ManualInputScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> tapKey(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(ValueKey('mathkey:$label')));
      await tester.pump();
    }

    String latexOf(WidgetTester tester) =>
        tester.widget<MathField>(find.byType(MathField)).controller.latex;

    testWidgets('digits go straight into the expression', (tester) async {
      await pumpKeyboard(tester);
      for (final digit in ['2', '3']) {
        await tapKey(tester, digit);
      }
      expect(latexOf(tester), '23');
    });

    testWidgets('the fraction key opens two boxes and lands in the first',
        (tester) async {
      await pumpKeyboard(tester);
      await tapKey(tester, 'fraction');
      final controller =
          tester.widget<MathField>(find.byType(MathField)).controller;
      expect(controller.latex, r'\frac{}{}');
      expect(controller.hasEmptySlot, isTrue);

      await tapKey(tester, '1');
      expect(latexOf(tester), r'\frac{1}{}');
    });

    testWidgets('x² wraps the number before it, calculator-style',
        (tester) async {
      await pumpKeyboard(tester);
      await tapKey(tester, '1');
      await tapKey(tester, '2');
      await tapKey(tester, 'squared');
      expect(latexOf(tester), '{12}^{2}');
    });

    testWidgets('the abc page types letters', (tester) async {
      await pumpKeyboard(tester);
      await tester.tap(find.text('abc'));
      await tester.pump();
      await tapKey(tester, 'y');
      expect(latexOf(tester), 'y');
    });

    testWidgets('every page lays out on a phone without overflowing',
        (tester) async {
      await pumpKeyboard(tester);
      for (final tab in MathKeyboard.tabs) {
        await tester.tap(find.byKey(ValueKey('mathtab:${tab.id}')));
        await tester.pump(); // not pumpAndSettle — the caret blinks forever
        final firstKey = tab.rows.first.firstWhere((k) => k != null)!;
        expect(
          find.byKey(ValueKey(MathKeyboard.keyOf(firstKey))),
          findsOneWidget,
          reason: tab.id,
        );
      }
      await tester.tap(find.text('abc'));
      await tester.pump();
      expect(find.byKey(const ValueKey('mathkey:a')), findsOneWidget);
    });

    testWidgets('survives large accessibility text', (tester) async {
      // The field caps its own scaling (a single row of math would otherwise
      // push the keyboard off-screen); the chrome around it must still fit.
      await pumpKeyboard(tester, textScale: 1.6);
      await tapKey(tester, 'fraction');
      expect(latexOf(tester), r'\frac{}{}');
    });

    testWidgets('backspace undoes the last keypress', (tester) async {
      await pumpKeyboard(tester);
      await tapKey(tester, '7');
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(latexOf(tester), isEmpty);
    });

    testWidgets('holding backspace clears the line without twelve taps',
        (tester) async {
      await pumpKeyboard(tester);
      for (final digit in ['1', '2', '3', '4', '5']) {
        await tapKey(tester, digit);
      }
      expect(latexOf(tester), '12345');

      final gesture =
          await tester.startGesture(tester.getCenter(
        find.byIcon(Icons.backspace_outlined),
      ));
      // One delete lands immediately; the rest arrive on the repeat timer.
      await tester.pump();
      expect(latexOf(tester), '1234');
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await gesture.up();
      await tester.pump();
      expect(latexOf(tester), isEmpty);
    });

    // The regression that shipped: enablement was computed in the screen's
    // build(), but typing only notified the controller — so the screen never
    // rebuilt and Solve stayed dead no matter what you keyed in.
    testWidgets('Solve wakes up the moment something is typed', (tester) async {
      await pumpKeyboard(tester);
      bool solveEnabled() => tester
          .getSemantics(find.byKey(MathKeyboard.solveKey))
          .flagsCollection.isEnabled == Tristate.isTrue;

      expect(solveEnabled(), isFalse, reason: 'nothing typed yet');

      await tapKey(tester, '5');
      expect(solveEnabled(), isTrue);

      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump();
      expect(solveEnabled(), isFalse, reason: 'back to empty');
    });

    testWidgets('an opened structure alone is enough to press Solve',
        (tester) async {
      // A bare `√□` has no digits in it, but the button must still respond —
      // validation is what explains the empty box, not a dead control.
      await pumpKeyboard(tester);
      await tapKey(tester, 'square root');
      expect(
        tester
            .getSemantics(find.byKey(MathKeyboard.solveKey))
            .flagsCollection.isEnabled == Tristate.isTrue,
        isTrue,
      );
    });

    testWidgets('the seven trig columns fit a phone without sideways scrolling',
        (tester) async {
      await pumpKeyboard(tester);
      await tester.tap(find.byKey(const ValueKey('mathtab:trigonometry')));
      await tester.pump();
      final grid = find.byKey(const ValueKey('trigonometry'));
      expect(grid, findsOneWidget);
      expect(
        find.ancestor(of: grid, matching: find.byType(SingleChildScrollView)),
        findsNothing,
        reason: 'a 1080px-wide phone has room for all seven columns',
      );
      expect(find.byKey(const ValueKey('mathkey:csc')), findsOneWidget);
    });
  });

  group('typed input is treated exactly like a scan after submission', () {
    test('manual LaTeX becomes a manual-source DetectedEquation (no OCR)', () async {
      const service = MockScannerService();
      final eq =
          await service.recognize(ScanSource.manual, manualLatex: r'2x + 5 = 13');
      expect(eq.source, ScanSource.manual);
      expect(eq.latex, r'2x + 5 = 13');
      expect(eq.confidence, 1);
      expect(eq.kind, EquationKind.linear);
    });

    test('recognizer classifies typed fractions', () async {
      const service = MockScannerService();
      final eq =
          await service.recognize(ScanSource.manual, manualLatex: r'\frac{3}{4}');
      expect(eq.source, ScanSource.manual);
      expect(eq.kind, EquationKind.fraction);
    });
  });
}
