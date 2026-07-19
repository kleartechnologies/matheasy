import 'package:flutter/material.dart';

import 'animation_primitive.dart';
import 'morph_op.dart';
import 'scene_spec.dart';

/// UNIVERSAL ANIMATED LEARNING ENGINE — the on-device animation contract.
///
/// An [AnimationScript] is the complete "watchable" walkthrough for one solved
/// problem, built ENTIRELY from the verified solve payload by
/// `AnimationScriptBuilder`. It carries the ordered [AnimationStep]s (each a
/// before→after morph with a primitive + phase), the persistent visual object
/// ([scene]) and the closing takeaways. Flutter only plays it — no math runs on
/// device beyond positioning already-verified tokens (golden rule).

/// The six named beats of the learning journey (the brief's timeline). Mapped
/// 1:1 from the backend `JourneyStageId` (takeaway → [answer]). The rail shows
/// these instead of anonymous "Step 3 of 6" dots.
enum LearningPhase {
  understand('Understand', Icons.lightbulb_outline_rounded),
  chooseMethod('Choose method', Icons.alt_route_rounded),
  apply('Apply the rule', Icons.bolt_rounded),
  simplify('Simplify', Icons.compress_rounded),
  verify('Verify', Icons.verified_outlined),
  answer('Answer', Icons.flag_rounded);

  const LearningPhase(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Playback speed for the universal control bar.
enum PlaybackSpeed {
  half('0.5×', 2.0),
  normal('1×', 1.0),
  oneAndHalf('1.5×', 1 / 1.5),
  double_('2×', 0.5);

  const PlaybackSpeed(this.label, this.durationScale);

  /// The chip label, e.g. `1.5×`.
  final String label;

  /// Multiplier applied to a step/morph [Duration] — slower speed ⇒ longer.
  final double durationScale;

  /// The next speed in the cycle (tapping the chip advances it).
  PlaybackSpeed get next => switch (this) {
        PlaybackSpeed.half => PlaybackSpeed.normal,
        PlaybackSpeed.normal => PlaybackSpeed.oneAndHalf,
        PlaybackSpeed.oneAndHalf => PlaybackSpeed.double_,
        PlaybackSpeed.double_ => PlaybackSpeed.half,
      };
}

/// One watchable beat: the transformation from [beforeLatex] to [afterLatex],
/// how to stage it ([primitive] + [morph]), which learning [phase] it belongs
/// to, and the plain-language "why".
@immutable
class AnimationStep {
  const AnimationStep({
    required this.title,
    required this.phase,
    required this.primitive,
    required this.beforeLatex,
    required this.afterLatex,
    required this.morph,
    required this.explanation,
    this.operationLabel,
    this.hint,
    this.isAnswer = false,
  });

  /// Short heading, e.g. "Subtract 5 from both sides".
  final String title;

  final LearningPhase phase;
  final AnimationPrimitive primitive;

  /// The equation before / after this beat (delimiter-free LaTeX, both verified).
  final String beforeLatex;
  final String afterLatex;

  /// The token-diff carrying [beforeLatex] into [afterLatex].
  final StepMorph morph;

  /// Why this move is valid, in student-friendly language.
  final String explanation;

  /// Optional transform chip, e.g. `− 5`.
  final String? operationLabel;

  /// Optional revealable hint.
  final String? hint;

  /// The final-answer beat (triggers the success celebration).
  final bool isAnswer;

  /// Screen-reader sentence for the whole transformation.
  String get semanticLabel =>
      '$title. $beforeLatex becomes $afterLatex. $explanation';
}

/// The complete animated walkthrough for one problem.
@immutable
class AnimationScript {
  const AnimationScript({
    required this.categoryLabel,
    required this.answerLatex,
    required this.intro,
    required this.steps,
    this.scene = SceneObject.none,
    this.keyIdeas = const [],
    this.methodName,
  });

  /// Human category label (e.g. "Linear equation") — display + analytics only.
  final String categoryLabel;

  /// The verified final answer as delimiter-free LaTeX.
  final String answerLatex;

  /// One warm sentence inviting the student to watch.
  final String intro;

  final List<AnimationStep> steps;

  /// The persistent visual object, revealed beat-by-beat (or [SceneObject.none]).
  final SceneObject scene;

  /// 1–3 closing takeaways.
  final List<String> keyIdeas;

  /// The named method the walkthrough follows, if any.
  final String? methodName;

  bool get isEmpty => steps.isEmpty;
  bool get hasScene => scene.isDrawable;

  /// The ordered, de-duplicated phases present in this script (for the timeline).
  List<LearningPhase> get phases {
    final seen = <LearningPhase>[];
    for (final s in steps) {
      if (!seen.contains(s.phase)) seen.add(s.phase);
    }
    return seen;
  }
}
