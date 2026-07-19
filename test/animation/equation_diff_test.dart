import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/result/application/animation/equation_diff.dart';
import 'package:matheasy/features/result/application/animation/equation_tokenizer.dart';
import 'package:matheasy/features/result/domain/animation/eq_token.dart';
import 'package:matheasy/features/result/domain/animation/morph_op.dart';

void main() {
  group('EquationTokenizer', () {
    test('splits a linear equation into signed terms + relation', () {
      final t = EquationTokenizer.tokenize('3x + 5 = 20');
      final terms = t.where((x) => x.isTerm).toList();
      expect(terms.map((x) => x.key).toList(), ['3x', '5', '20']);
      expect(terms.map((x) => x.side).toList(), [0, 0, 1]);
      expect(terms.map((x) => x.sign).toList(), [1, 1, 1]);
      expect(t.where((x) => x.isRelation).length, 1);
      expect(t.firstWhere((x) => x.isRelation).latex, '=');
    });

    test('captures a leading negative sign', () {
      final t = EquationTokenizer.tokenize('-5x + 6 = 0');
      final terms = t.where((x) => x.isTerm).toList();
      expect(terms[0].key, '5x');
      expect(terms[0].sign, -1);
      expect(terms[1].sign, 1);
    });

    test('does not split inside braces / parens / fractions', () {
      final t = EquationTokenizer.tokenize(r'\frac{a-b}{c} = 0');
      final terms = t.where((x) => x.isTerm).toList();
      expect(terms.length, 2);
      expect(terms.first.key, r'\frac{a-b}{c}');
    });

    test('strips \\left \\right wrappers and keeps the bracket as one term', () {
      final t = EquationTokenizer.tokenize(r'\left(x+1\right) = 0');
      final terms = t.where((x) => x.isTerm).toList();
      expect(terms.length, 2);
      expect(terms.first.key, '(x+1)');
    });

    test('blank input yields no tokens', () {
      expect(EquationTokenizer.tokenize('   '), isEmpty);
    });
  });

  group('EquationDiff', () {
    List<EqToken> tk(String s) => EquationTokenizer.tokenize(s);

    test('a term sliding across = is a confident cross-relation move', () {
      final m = EquationDiff.diff(tk('3x + 5 = 20'), tk('3x = 20 - 5'));
      expect(m.confident, isTrue);
      expect(m.crossedRelation, isTrue);
      // The "5" term is matched by key across the relation → a move op.
      final moves = m.ops.where((o) => o.kind == MorphKind.move).toList();
      expect(moves, isNotEmpty);
      // 3x and 20 stay put.
      expect(m.ops.where((o) => o.kind == MorphKind.keep).length, 2);
    });

    test('two terms collapsing into one is a merge', () {
      final m = EquationDiff.diff(tk('3x = 20 - 5'), tk('3x = 15'));
      expect(m.merged, isTrue);
      final merge = m.ops.where((o) => o.kind == MorphKind.merge).toList();
      expect(merge, hasLength(1));
      expect(merge.first.fromIds.length, 2); // 20 and -5
      expect(merge.first.toIds.length, 1); // 15
    });

    test('an unchanged equation keeps every term', () {
      final m = EquationDiff.diff(tk('x = 4'), tk('x = 4'));
      expect(m.confident, isTrue);
      expect(m.ops.every((o) => o.kind == MorphKind.keep), isTrue);
      expect(m.crossedRelation, isFalse);
    });

    test('a whole-value rewrite with no shared terms is low-confidence', () {
      // 2x=8 → x=4 shares no term keys ("2x"≠"x", "8"≠"4"); the view crossfades.
      final m = EquationDiff.diff(tk('2x = 8'), tk('x = 4'));
      expect(m.confident, isFalse);
    });

    test('never throws on messy input', () {
      expect(() => EquationDiff.diff(tk(r'\int_0^1 x^2 dx'), tk('x^3/3')),
          returnsNormally);
    });
  });
}
