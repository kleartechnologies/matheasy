/// Where a scanned problem came from.
enum ScanSource {
  /// Live camera capture (the shutter).
  camera,

  /// Picked from the photo library.
  gallery,

  /// Typed in manually.
  manual,

  /// Built from a practice question (the V5 hint ladder / Show Solution
  /// path). Solves from this source ride the rate-limited, un-metered solve
  /// path — the question itself was already metered at generation by the
  /// `practiceQuestions` quota, so a solution reveal must not also burn a
  /// scan (see docs/matheasy-anti-abuse-security.md).
  practice,
}
