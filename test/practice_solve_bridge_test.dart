// PracticeSolveBridge — the gate deciding which practice questions may ride
// the verified solve pipeline (hint level 3 / Show Solution / Review). Only
// typed questions with clean LaTeX and no figure qualify; everything else
// falls back to the question's own deterministic explanation.

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/practice/application/practice_solve_bridge.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_figure.dart';
import 'package:matheasy/features/practice/domain/practice_question.dart';
import 'package:matheasy/features/practice/domain/practice_topic.dart';
import 'package:matheasy/features/scan/domain/detected_equation.dart';
import 'package:matheasy/features/scan/domain/scan_source.dart';

PracticeQuestion _q({
  PracticeQuestionType type = PracticeQuestionType.equation,
  String? promptLatex = '2x + 5 = 13',
  PracticeFigure? figure,
  PracticeTopic topic = PracticeTopic.algebra,
}) =>
    PracticeQuestion(
      id: 'q',
      topic: topic,
      difficulty: PracticeDifficulty.medium,
      type: type,
      prompt: 'Solve for x',
      promptLatex: promptLatex,
      explanation: 'why',
      acceptedAnswers: const ['4'],
      figure: figure,
    );

void main() {
  group('PracticeSolveBridge.equationFor', () {
    test('an equation question with LaTeX rides the pipeline', () {
      final eq = PracticeSolveBridge.equationFor(_q())!;
      expect(eq.latex, '2x + 5 = 13');
      expect(eq.source, ScanSource.practice);
      expect(eq.confidence, 1.0);
      expect(eq.kind, EquationKind.linear);
    });

    test('input questions qualify too', () {
      expect(
        PracticeSolveBridge.equationFor(_q(type: PracticeQuestionType.input)),
        isNotNull,
      );
    });

    test('no LaTeX → no pipeline', () {
      expect(PracticeSolveBridge.equationFor(_q(promptLatex: null)), isNull);
      expect(PracticeSolveBridge.equationFor(_q(promptLatex: '  ')), isNull);
    });

    test('choice questions never ride the pipeline', () {
      expect(
        PracticeSolveBridge.equationFor(
            _q(type: PracticeQuestionType.multipleChoice)),
        isNull,
      );
      expect(
        PracticeSolveBridge.equationFor(
            _q(type: PracticeQuestionType.trueFalse)),
        isNull,
      );
    });

    test('a figure question never rides the pipeline', () {
      // The figure carries facts the LaTeX doesn't — solving the LaTeX alone
      // could contradict the drawing.
      const figure = PracticeFigure(
        kind: PracticeFigureKind.circle,
        semanticsLabel: 'A circle',
        circleLabel: '3',
      );
      expect(PracticeSolveBridge.equationFor(_q(figure: figure)), isNull);
    });

    test('a practice-sourced solve never counts as a scan', () {
      // Mirrors FunctionsSolverService: countAsScan is `source == manual`.
      final eq = PracticeSolveBridge.equationFor(_q())!;
      expect(eq.source == ScanSource.manual, isFalse);
    });

    test('every topic maps to an EquationKind', () {
      for (final topic in PracticeTopic.values) {
        expect(PracticeSolveBridge.kindFor(topic), isA<EquationKind>(),
            reason: topic.name);
      }
    });
  });
}
