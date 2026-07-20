import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/widgets/chat/rich_math_text.dart';

Widget _host(String text) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: RichMathText(text, style: const TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );

/// The concatenated plain text of every Text/Text.rich in the tree (excludes the
/// WidgetSpan math placeholders), so we can assert what prose actually renders.
String _plain(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final element in find.byType(Text).evaluate()) {
    final widget = element.widget as Text;
    buffer.write(widget.data ??
        widget.textSpan?.toPlainText(
          includeSemanticsLabels: false,
          includePlaceholders: false,
        ) ??
        '');
  }
  return buffer.toString();
}

void main() {
  testWidgets('renders inline \$...\$ as real math, keeps the prose',
      (tester) async {
    await tester.pumpWidget(
        _host(r'To solve $2x = 4$, divide by 2 to get $x = 2$. Nice work!'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsNWidgets(2));
    final text = _plain(tester);
    expect(text, contains('divide by 2'));
    expect(text, isNot(contains(r'$2x')));
  });

  testWidgets('an align environment renders, never leaking raw \\begin / & / \\\\',
      (tester) async {
    await tester.pumpWidget(_host(
        r'Solve the system: $$\begin{align} x + y &= 3 \\ x - y &= 1 \end{align}$$'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final text = _plain(tester);
    expect(text, isNot(contains('begin')));
    expect(text, isNot(contains(r'\\')));
    expect(text, isNot(contains('&')));
  });

  testWidgets('bare LaTeX with no \$ wrapper still renders as math, not raw',
      (tester) async {
    await tester.pumpWidget(
        _host(r'The derivative is \frac{d}{dx} of the curve here.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsWidgets);
    final text = _plain(tester);
    expect(text, contains('The derivative is'));
    expect(text, isNot(contains(r'\frac')));
  });

  testWidgets('an unmatched \$ drops the stray sign and still renders the math',
      (tester) async {
    await tester
        .pumpWidget(_host(r'Solve where $x = \frac{-b}{2a} and continue.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsWidgets);
    final text = _plain(tester);
    expect(text, contains('Solve where'));
    expect(text, contains('and continue'));
    expect(text, isNot(contains(r'$')));
    expect(text, isNot(contains(r'\frac')));
  });

  testWidgets('two money \$ signs stay as currency prose, not merged math',
      (tester) async {
    await tester.pumpWidget(
        _host(r'A pizza costs $8 and a drink costs $3, so $11 total.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(Math), findsNothing);
    final text = _plain(tester);
    expect(text, contains(r'$8'));
    expect(text, contains(r'$3'));
  });

  testWidgets('a code fence is unwrapped (keeps the working), never blank',
      (tester) async {
    await tester.pumpWidget(_host(
        'Here is the solution:\n```\n2x + 3 = 7\n2x = 4\nx = 2\n```\nHope that helps!'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final text = _plain(tester);
    expect(text, isNot(contains('```')));
    expect(text, contains('2x + 3 = 7')); // the working survives
    expect(text, contains('x = 2'));
  });

  testWidgets('a whole-reply fence does not blank the bubble', (tester) async {
    await tester.pumpWidget(_host('```\nx = 5\n```'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_plain(tester).trim(), contains('x = 5'));
  });

  testWidgets('a lone leading "- 5" (negative) is not turned into a bullet',
      (tester) async {
    await tester.pumpWidget(_host('Move left:\n- 5 means five steps left'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final text = _plain(tester);
    expect(text, contains('- 5'));
    expect(text, isNot(contains('•')));
  });

  testWidgets('a real bulleted list (2+) is normalised to •', (tester) async {
    await tester.pumpWidget(_host('Steps:\n- add 3\n- divide by 2'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_plain(tester), contains('• add 3'));
  });

  testWidgets('"#3" as an ordinal keeps its hash; a real heading is stripped',
      (tester) async {
    await tester.pumpWidget(_host('# Solution\n#3 is the third term'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final text = _plain(tester);
    expect(text, contains('#3 is the third term'));
    expect(text, isNot(contains('# Solution')));
    expect(text, contains('Solution'));
  });

  testWidgets('strips code fences/backticks and renders **bold**; never throws',
      (tester) async {
    await tester.pumpWidget(
        _host(r'This is **key**: use `inline` code $\frac{oops$ still fine.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final text = _plain(tester);
    expect(text, contains('key'));
    expect(text, isNot(contains('`')));
  });
}
