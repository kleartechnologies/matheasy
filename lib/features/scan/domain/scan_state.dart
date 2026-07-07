import 'detected_equation.dart';

/// The scanner's finite state machine.
///
/// ```
/// ScanIdle ──(live detect)──▶ ScanDetecting ──(capture)──▶ ScanCaptured
///    ▲                                                          │
///    └──────────────(retake)────────────────────────────────── │
///                                                    (confirm)  ▼
///                          ScanComplete ◀──(done)── ScanProcessing
/// ```
///
/// Sealed so the UI can switch over it exhaustively.
sealed class ScanState {
  const ScanState();
}

/// Camera is live; no candidate detected yet.
class ScanIdle extends ScanState {
  const ScanIdle();
}

/// A candidate equation is being detected live in the frame.
class ScanDetecting extends ScanState {
  const ScanDetecting(this.candidate);
  final DetectedEquation candidate;
}

/// The user captured a problem; awaiting confirmation (retake / continue).
class ScanCaptured extends ScanState {
  const ScanCaptured(this.equation);
  final DetectedEquation equation;
}

/// The captured problem is being analyzed.
class ScanProcessing extends ScanState {
  const ScanProcessing(this.equation);
  final DetectedEquation equation;
}

/// Processing finished; ready to hand off to the result screen.
class ScanComplete extends ScanState {
  const ScanComplete(this.equation);
  final DetectedEquation equation;
}

/// Something went wrong (e.g. nothing recognized).
class ScanError extends ScanState {
  const ScanError(this.message);
  final String message;
}
