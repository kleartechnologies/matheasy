import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/theme/app_theme.dart';
import 'package:matheasy/features/scan/application/scanner_service.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/math_input.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';
import 'package:matheasy/features/scan/presentation/manual_input_screen.dart';
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

  group('MathInput.isBalanced', () {
    test('balanced mixed brackets', () {
      expect(MathInput.isBalanced(r'\sqrt{(x+1)}[2]'), isTrue);
    });
    test('wrong closing order is unbalanced', () {
      expect(MathInput.isBalanced('([)]'), isFalse);
    });
  });

  group('math keyboard covers every required educational category', () {
    final inserts =
        MathKeyboard.categories.expand((c) => c.keys).map((k) => k.insert).join(' ');

    test('fractions, exponents, roots, parens, variables, trig, calc, logs', () {
      expect(inserts, contains(r'\frac'), reason: 'fractions');
      expect(inserts, contains('^{'), reason: 'exponents');
      expect(inserts, contains(r'\sqrt'), reason: 'square roots');
      expect(inserts, contains('('), reason: 'parentheses');
      expect(inserts, contains('x'), reason: 'variables');
      expect(inserts, contains(r'\sin'), reason: 'trigonometry');
      expect(inserts, contains(r'\int'), reason: 'calculus');
      expect(inserts, contains(r'\log'), reason: 'logarithms');
    });

    test('exposes at least six categories', () {
      expect(MathKeyboard.categories.length, greaterThanOrEqualTo(6));
    });

    test('template keys carry a caretBack so the caret lands in a placeholder', () {
      final frac = MathKeyboard.categories
          .expand((c) => c.keys)
          .firstWhere((k) => k.insert == r'\frac{}{}');
      expect(frac.caretBack, greaterThan(0));
    });
  });

  group('the keyboard BUILDS structured nested LaTeX, not flat text (§6)', () {
    Future<void> pumpKeyboard(WidgetTester tester) async {
      // A phone-sized surface so the full keyboard + preview lay out without
      // overflowing the default 800×600 test viewport.
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const ManualInputScreen(),
          ),
        ),
      );
      await tester.pump(); // let focus settle
    }

    testWidgets('a fraction with an exponent inside → \\frac{x^{2}}{3}',
        (tester) async {
      await pumpKeyboard(tester);
      // a⁄b (fraction template) → x → x² (exponent template) → move right ×2
      // to cross out of the numerator into the denominator → 3.
      for (final label in ['a⁄b', 'x', 'x²']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pump();
      await tester.tap(find.text('3'));
      await tester.pump();

      // Structured, brace-delimited — NOT a flat "x^2/3" string. This is the LaTeX
      // that (with the §6 normalizer fix) now round-trips to solve().
      expect(find.text(r'\frac{x^{2}}{3}'), findsOneWidget);
    });

    testWidgets('a root over an expression → \\sqrt{x+1}', (tester) async {
      await pumpKeyboard(tester);
      for (final label in ['√', 'x', '+', '1']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(find.text(r'\sqrt{x+1}'), findsOneWidget);
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
