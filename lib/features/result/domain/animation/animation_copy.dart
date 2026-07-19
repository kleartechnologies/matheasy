import 'package:flutter/foundation.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — localized copy for the SYNTHETIC beats
/// the builder adds (understand / verify / answer) and the intro.
///
/// The transform beats reuse the solver's already-localized `title`/`detail`, so
/// only these few framing strings need the app's locale. The widget layer builds
/// one of these from `context.l10n`; [fallback] keeps the builder unit-testable
/// and gives a safe English default if a key is ever missing.
@immutable
class AnimationCopy {
  const AnimationCopy({
    required this.intro,
    required this.understandTitle,
    required this.understandDetail,
    required this.verifyTitle,
    required this.answerTitle,
    required this.answerDetail,
  });

  /// One warm sentence inviting the student to watch.
  final String intro;

  final String understandTitle;
  final String understandDetail;
  final String verifyTitle;
  final String answerTitle;

  /// The closing line — `{answer}` is replaced with the verified answer LaTeX's
  /// plain form by the builder is NOT done here; this is a plain sentence.
  final String answerDetail;

  /// Safe English default (also what the unit tests use).
  static const AnimationCopy fallback = AnimationCopy(
    intro: 'Watch the solution come to life, one change at a time.',
    understandTitle: 'Understand the problem',
    understandDetail: "First, let's look at exactly what we're solving.",
    verifyTitle: 'Check it works',
    answerTitle: "You've got it!",
    answerDetail: 'This is the solution — every step led here.',
  );
}
