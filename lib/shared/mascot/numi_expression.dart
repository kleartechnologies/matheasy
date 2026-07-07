/// The set of Numi mascot expressions used across the app.
///
/// This enum is the stable contract every screen depends on. When the Rive
/// asset lands, each value maps to a state-machine input — call sites never
/// change.
enum NumiExpression {
  /// Default friendly resting face.
  idle,

  /// Warm, engaged smile — the everyday state.
  happy,

  /// Excited, eyes-closed cheer for wins (correct answers, unlocks).
  celebrate,

  /// Pondering — used while "typing"/processing.
  thinking,

  /// Playful wink — encouragement.
  wink,

  /// Waving hello — onboarding / greetings.
  wave,
}
