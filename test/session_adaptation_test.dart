// SessionAdaptation — the pure V5 mid-session difficulty policy: 3 first-try
// clean corrects raise, 2 struggled finals lower, everything stays within ±1
// of the chosen centre and under the tier ceiling (free tops out at medium).

import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/features/practice/application/engine/session_adaptation.dart';
import 'package:matheasy/features/practice/domain/practice_difficulty.dart';
import 'package:matheasy/features/practice/domain/practice_session.dart';

PracticeAnswer _clean(int i) => PracticeAnswer(
      questionId: 'q$i',
      submitted: 'x',
      isCorrect: true,
      xpEarned: 10,
    );

PracticeAnswer _wrong(int i) => PracticeAnswer(
      questionId: 'q$i',
      submitted: 'x',
      isCorrect: false,
      xpEarned: 0,
    );

PracticeAnswer _hinted(int i) => PracticeAnswer(
      questionId: 'q$i',
      submitted: 'x',
      isCorrect: true,
      xpEarned: 7,
      hintLevelUsed: 2,
    );

void main() {
  const adaptation = SessionAdaptation();

  SessionShift decide(
    List<PracticeAnswer> answers, {
    PracticeDifficulty current = PracticeDifficulty.medium,
    PracticeDifficulty centre = PracticeDifficulty.medium,
    bool isPro = true,
  }) =>
      adaptation.decide(
        answers: answers,
        current: current,
        centre: centre,
        isPro: isPro,
      );

  group('raise', () {
    test('three first-try clean corrects in a row raise one notch', () {
      expect(
        decide([_clean(1), _clean(2), _clean(3)]),
        SessionShift.raise,
      );
    });

    test('two are not enough', () {
      expect(decide([_clean(1), _clean(2)]), SessionShift.hold);
    });

    test('a hint inside the streak breaks it', () {
      expect(
        decide([_clean(1), _hinted(2), _clean(3)]),
        SessionShift.hold,
      );
    });

    test('never drifts more than one notch above the centre', () {
      expect(
        decide(
          [_clean(1), _clean(2), _clean(3)],
          current: PracticeDifficulty.hard, // already centre+1
        ),
        SessionShift.hold,
      );
    });

    test('the free tier never rises past medium', () {
      expect(
        decide(
          [_clean(1), _clean(2), _clean(3)],
          isPro: false,
        ),
        SessionShift.hold,
      );
    });

    test('expert has nowhere to rise', () {
      expect(
        decide(
          [_clean(1), _clean(2), _clean(3)],
          current: PracticeDifficulty.expert,
          centre: PracticeDifficulty.expert,
        ),
        SessionShift.hold,
      );
    });
  });

  group('lower', () {
    test('two incorrect finals in a row lower one notch', () {
      expect(decide([_wrong(1), _wrong(2)]), SessionShift.lower);
    });

    test('two heavily-hinted corrects also lower', () {
      expect(decide([_hinted(1), _hinted(2)]), SessionShift.lower);
    });

    test('a clean correct in between resets the struggle', () {
      expect(decide([_wrong(1), _clean(2)]), SessionShift.hold);
    });

    test('never drifts more than one notch below the centre', () {
      expect(
        decide(
          [_wrong(1), _wrong(2)],
          current: PracticeDifficulty.easy, // already centre−1
        ),
        SessionShift.hold,
      );
    });

    test('veryEasy has nowhere to fall', () {
      expect(
        decide(
          [_wrong(1), _wrong(2)],
          current: PracticeDifficulty.veryEasy,
          centre: PracticeDifficulty.veryEasy,
        ),
        SessionShift.hold,
      );
    });
  });

  test('an empty session holds', () {
    expect(decide(const []), SessionShift.hold);
  });

  test('a raise streak beats a stale struggle further back', () {
    expect(
      decide([_wrong(1), _wrong(2), _clean(3), _clean(4), _clean(5)]),
      SessionShift.raise,
    );
  });
}
