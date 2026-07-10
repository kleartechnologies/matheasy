import 'detected_equation.dart';

/// The scanner's finite state machine.
///
/// ```
/// ScanIdle ──(capture/crop/type)──▶ ScanRecognizing ──(ok)──▶ ScanCaptured
///    ▲                                     │                        │
///    └───────────(retake)──────────────────┴──(error)──▶ ScanError  │
///                                                     (confirm)      ▼
///                                              ScanComplete ◀────────┘
/// ```
///
/// Recognition (`ScanRecognizing`) is a real OpenAI Vision round-trip; the
/// downstream solve happens on the result screen. Sealed so the UI can switch
/// over it exhaustively.
sealed class ScanState {
  const ScanState();
}

/// Camera preview is live; nothing captured yet.
class ScanIdle extends ScanState {
  const ScanIdle();
}

/// A captured/cropped photo (or typed problem) is being recognized server-side.
class ScanRecognizing extends ScanState {
  const ScanRecognizing();
}

/// The problem was recognized; awaiting confirmation (retake / continue).
class ScanCaptured extends ScanState {
  const ScanCaptured(this.equation);
  final DetectedEquation equation;
}

/// The user confirmed the capture; ready to hand off to the result screen
/// (which runs the real solve).
class ScanComplete extends ScanState {
  const ScanComplete(this.equation);
  final DetectedEquation equation;
}

/// Recognition failed — blurry / empty / non-math image, or a network/backend
/// error. [canRetry] gates whether the retry affordance is shown.
class ScanError extends ScanState {
  const ScanError(this.message, {this.canRetry = true});
  final String message;
  final bool canRetry;
}

/// The server rejected the scan because the free-tier quota is exhausted. The
/// screen listens for this and routes to the paywall (scan-limit trigger)
/// instead of showing a raw error.
class ScanQuotaExceeded extends ScanState {
  const ScanQuotaExceeded();
}
