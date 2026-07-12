/// Decides when the phone has been held steady long enough to auto-capture
/// (spec §10). Pure logic over accelerometer magnitude samples so it's fully
/// unit-testable without the sensor.
///
/// The signal is the *user* acceleration magnitude (gravity removed): ≈0 when
/// held still, spiking when the phone moves. Auto-capture is a nice-to-have that
/// sits BEHIND the manual shutter — it only ever *triggers* the existing capped
/// capture flow, so it can't add an uncapped path or destabilize the scanner.
///
/// Fire-once semantics: it becomes ready after [steadyWindow] of stillness while
/// *armed*, then the caller [disarm]s it; it only re-arms when a deliberate move
/// (a magnitude spike over [moveThreshold]) is seen — so pointing at one problem
/// never machine-guns captures; you move to the next problem to re-arm.
class SteadinessDetector {
  SteadinessDetector({
    this.steadyWindow = const Duration(milliseconds: 800),
    this.stillThreshold = 0.35,
    this.moveThreshold = 1.5,
  });

  /// How long the phone must stay still before auto-capture is ready.
  final Duration steadyWindow;

  /// Magnitude (m/s²) at or below which the phone counts as "still".
  final double stillThreshold;

  /// Magnitude (m/s²) above which a move re-arms after a capture.
  final double moveThreshold;

  int? _steadySinceMs;
  bool _armed = true;

  /// Feeds one acceleration [magnitude] sample at [tMillis] and returns true
  /// when the phone has been still for [steadyWindow] while armed. Does NOT
  /// disarm — the caller [disarm]s only if it actually fires (so a sample that
  /// arrives while the scanner is busy doesn't waste the "ready").
  bool isReadyToCapture(double magnitude, int tMillis) {
    if (magnitude > moveThreshold) {
      _armed = true; // a deliberate move → the user is re-aiming
      _steadySinceMs = null;
      return false;
    }
    if (magnitude > stillThreshold) {
      _steadySinceMs = null; // drifting — restart the stillness clock
      return false;
    }
    _steadySinceMs ??= tMillis;
    return _armed && tMillis - _steadySinceMs! >= steadyWindow.inMilliseconds;
  }

  /// Marks that a capture just fired: don't fire again until a move re-arms.
  void disarm() {
    _armed = false;
    _steadySinceMs = null;
  }

  /// 0..1 progress toward the next auto-capture (for an optional steadiness
  /// indicator). 0 while moving or disarmed.
  double progress(int tMillis) {
    final since = _steadySinceMs;
    if (!_armed || since == null) return 0;
    final elapsed = tMillis - since;
    final ratio = elapsed / steadyWindow.inMilliseconds;
    return ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
  }
}
