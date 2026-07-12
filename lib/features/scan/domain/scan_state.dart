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

/// Why recognition failed — drives the §9 voice + the right next action.
enum ScanErrorKind {
  /// The image was read but held no legible math ("try again or type it in").
  couldntRecognize,

  /// The recognition request never reached the server ("you're offline").
  offline,

  /// An unexpected server / client failure (calm retry).
  generic,
}

/// Recognition failed — blurry / empty / non-math image, a network drop, or a
/// backend error. [kind] selects the honest §9 state to show; [message] is the
/// underlying detail (kept for logging / the generic case).
class ScanError extends ScanState {
  const ScanError(
    this.message, {
    this.kind = ScanErrorKind.generic,
    this.canRetry = true,
  });
  final String message;
  final ScanErrorKind kind;
  final bool canRetry;
}

/// The server rejected the scan because the free-tier quota is exhausted. The
/// screen listens for this and routes to the paywall (scan-limit trigger)
/// instead of showing a raw error.
class ScanQuotaExceeded extends ScanState {
  const ScanQuotaExceeded();
}
