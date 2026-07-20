import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/widgets/chat/rich_math_text.dart';

Widget _host(String text) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: RichMathText(text, style: const TextStyle(fontSize: 16)),
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
  testWidgets('renders inline \$...\$ as real math, keeps the prose', (tester) async {
    await tester.pumpWidget(
        _host(r'To solve $2x = 4$, divide by 2 to get $x = 2$. Nice work!'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Two inline equations became real math, not literal "$2x = 4$".
    expect(find.byType(Math), findsNWidgets(2));
    final text = _plain(tester);
    expect(text, contains('divide by 2'));
    expect(text, isNot(contains(r'$2x')));
  });

  testWidgets('strips code fences, backticks, headings and bullet markup',
      (tester) async {
    await tester.pumpWidget(_host(
        '# Heading\nHere is code ```dart\nprint(1);\n``` and `inline` bits.\n- one\n- two'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final text = _plain(tester);
    expect(text, isNot(contains('```')));
    expect(text, isNot(contains('`')));
    expect(text, isNot(contains('print(1)'))); // fenced code removed entirely
    expect(text, isNot(contains('# Heading'))); // hash stripped
    expect(text, contains('Heading'));
    expect(text, contains('• one')); // bullets normalised
  });

  testWidgets('renders **bold** and never throws on malformed LaTeX',
      (tester) async {
    await tester.pumpWidget(_host(r'This is **important**: $\frac{oops$ still fine.'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_plain(tester), contains('important'));
  });
}
