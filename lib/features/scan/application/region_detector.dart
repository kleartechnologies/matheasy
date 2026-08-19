import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/monitoring/logging_service.dart';
import '../domain/math_text_scorer.dart';

/// Finds WHERE the maths is in a captured still, entirely on-device.
///
/// This is a locator, never a transcriber. Everything it returns is a list of
/// [DetectedTextBlock]s — rectangles plus the rough characters that justify
/// them — which the crop screen folds into a *suggested* crop the student can
/// always override. The characters ML Kit saw are used to decide whether a
/// block looks like maths and then discarded, because a line-text recogniser
/// cannot represent two-dimensional notation and the verification gate
/// substitutes back into the problem AS TRANSCRIBED: a misread that reached
/// the solver would verify perfectly and return a confidently wrong answer.
/// OpenAI Vision remains the only transcriber.
///
/// It runs only on a frozen capture, after the shutter — never against the
/// live preview. The preview stays a plain 60fps camera feed with static
/// guides; analysis starts when there is a still worth analysing.
abstract class RegionDetector {
  /// Read the text blocks in a captured still at [path], in that image's own
  /// pixel space.
  ///
  /// Unnormalised on purpose. Normalising needs the image's displayed size,
  /// which costs a decode — and that decode does not depend on this read, so
  /// the caller runs the two at the same time and folds them together with
  /// [regionFromBlocks]. Returning a region from here would have forced the
  /// size to be known first and put the decode back on the critical path.
  Future<List<DetectedTextBlock>> readBlocks(String path);

  Future<void> dispose();
}

/// The detector used when ML Kit isn't available — an unsupported platform, a
/// widget test, a device where the model failed to load.
///
/// Everything downstream treats "no blocks" as "no suggestion, let the user
/// frame the crop themselves", which is exactly the manual behaviour. That is
/// the point: the suggested crop is an assist layered over a flow that already
/// works without it, and the scanner must degrade to the manual crop rather
/// than to a broken one.
class NoopRegionDetector implements RegionDetector {
  const NoopRegionDetector();

  @override
  Future<List<DetectedTextBlock>> readBlocks(String path) async => const [];

  @override
  Future<void> dispose() async {}
}

/// [RegionDetector] backed by ML Kit's on-device Latin text recogniser.
///
/// The model is bundled with the app and runs offline, so a detection costs no
/// network, no quota and no money — which is what makes it safe to run against
/// every capture.
class MlKitRegionDetector implements RegionDetector {
  MlKitRegionDetector();

  // Latin script — the default, and the only one whose model is worth loading
  // for maths: digits and operators are shared across scripts anyway.
  final TextRecognizer _recognizer = TextRecognizer();

  bool _disposed = false;

  /// True once a detection has thrown. ML Kit failing is not worth retrying —
  /// the first failure quietly retires the suggested crop and the crop screen
  /// simply opens without a pre-framed rectangle.
  bool _broken = false;

  @override
  Future<List<DetectedTextBlock>> readBlocks(String path) async {
    if (_disposed || _broken) return const [];
    try {
      final recognized =
          await _recognizer.processImage(InputImage.fromFilePath(path));
      if (_disposed) return const [];
      return [
        for (final block in recognized.blocks)
          DetectedTextBlock(
            text: block.text,
            bounds: ui.Rect.fromLTRB(
              block.boundingBox.left,
              block.boundingBox.top,
              block.boundingBox.right,
              block.boundingBox.bottom,
            ),
          ),
      ];
    } catch (error) {
      _broken = true;
      LoggingService.warning('On-device region detection disabled: $error');
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _recognizer.close();
  }
}

/// Builds the detector for this platform.
///
/// ML Kit ships bindings for Android and iOS only; everywhere else (and in the
/// widget tests, which have no platform channels) the crop screen runs on the
/// no-op and simply opens without a suggested crop.
RegionDetector createRegionDetector() {
  if (kIsWeb) return const NoopRegionDetector();
  try {
    if (Platform.isAndroid || Platform.isIOS) return MlKitRegionDetector();
  } catch (_) {
    // Platform is unavailable in some test environments.
  }
  return const NoopRegionDetector();
}
