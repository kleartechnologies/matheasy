import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../core/monitoring/logging_service.dart';
import '../domain/detected_region.dart';
import '../domain/math_text_scorer.dart';

/// Finds WHERE the maths is on the page, entirely on-device.
///
/// This is a locator, never a transcriber. Everything it returns is a
/// [DetectedRegion] — a rectangle and a rough "does this look like maths"
/// score — and the type deliberately has nowhere to put a reading. The
/// characters ML Kit saw are used to decide whether a box is worth drawing and
/// then discarded, because a line-text recogniser cannot represent two
/// dimensional notation and the verification gate substitutes back into the
/// problem AS TRANSCRIBED: a misread that reached the solver would verify
/// perfectly and return a confidently wrong answer. OpenAI Vision remains the
/// only transcriber. See docs/matheasy-scanner-performance-audit.md §6.
abstract class RegionDetector {
  /// Detect in a live preview frame. Returns [DetectedRegion.none] when the
  /// frame holds nothing, or when detection isn't available at all.
  Future<DetectedRegion> detectInFrame(
    CameraImage image, {
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required bool isFrontCamera,
  });

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
/// Everything downstream treats [DetectedRegion.none] as "no box, upload the
/// whole frame", which is exactly the pre-existing behaviour. That is the point:
/// live detection is an accelerator, and the scanner must degrade to the old
/// pipeline rather than to a broken one.
class NoopRegionDetector implements RegionDetector {
  const NoopRegionDetector();

  @override
  Future<DetectedRegion> detectInFrame(
    CameraImage image, {
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required bool isFrontCamera,
  }) async =>
      DetectedRegion.none;

  @override
  Future<List<DetectedTextBlock>> readBlocks(String path) async => const [];

  @override
  Future<void> dispose() async {}
}

/// Maps a device orientation onto the degrees Android must rotate a camera
/// frame by before ML Kit reads it.
const Map<DeviceOrientation, int> _rotationCompensation = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};

/// [RegionDetector] backed by ML Kit's on-device Latin text recogniser.
///
/// The model is bundled with the app and runs offline, so a detection costs no
/// network, no quota and no money — which is what makes it safe to run
/// continuously against the preview.
class MlKitRegionDetector implements RegionDetector {
  MlKitRegionDetector();

  // Latin script — the default, and the only one whose model is worth loading
  // for maths: digits and operators are shared across scripts anyway.
  final TextRecognizer _recognizer = TextRecognizer();

  bool _disposed = false;

  /// True once a detection has thrown. ML Kit failing is not worth retrying at
  /// frame rate — a broken recogniser would throw thirty times a second and
  /// bury the log — so the first failure quietly retires live detection and the
  /// scanner falls back to uploading the full frame.
  bool _broken = false;

  @override
  Future<DetectedRegion> detectInFrame(
    CameraImage image, {
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required bool isFrontCamera,
  }) async {
    if (_disposed || _broken) return DetectedRegion.none;
    final input = _inputFromCameraImage(
      image,
      sensorOrientation: sensorOrientation,
      deviceOrientation: deviceOrientation,
      isFrontCamera: isFrontCamera,
    );
    if (input == null) return DetectedRegion.none;

    // ML Kit reports boxes in the space it read, which is the frame ROTATED by
    // the value above. At a quarter turn the frame's width and height trade
    // places, so normalising against the unrotated size would squash the box
    // into the wrong half of the screen.
    final rotation = input.metadata?.rotation;
    final quarterTurned = rotation == InputImageRotation.rotation90deg ||
        rotation == InputImageRotation.rotation270deg;
    final size = quarterTurned
        ? ui.Size(image.height.toDouble(), image.width.toDouble())
        : ui.Size(image.width.toDouble(), image.height.toDouble());

    return _process(input, size);
  }

  @override
  Future<List<DetectedTextBlock>> readBlocks(String path) async {
    if (_disposed || _broken) return const [];
    return _read(InputImage.fromFilePath(path));
  }

  Future<DetectedRegion> _process(InputImage input, ui.Size size) async =>
      regionFromBlocks(await _read(input), size);

  Future<List<DetectedTextBlock>> _read(InputImage input) async {
    try {
      final recognized = await _recognizer.processImage(input);
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

  /// Wraps a preview frame for ML Kit, or returns null when this frame's format
  /// isn't one ML Kit accepts.
  InputImage? _inputFromCameraImage(
    CameraImage image, {
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required bool isFrontCamera,
  }) {
    final rotation = _rotationFor(
      sensorOrientation: sensorOrientation,
      deviceOrientation: deviceOrientation,
      isFrontCamera: isFrontCamera,
    );
    if (rotation == null) return null;

    final raw = image.format.raw;
    final format =
        raw is int ? InputImageFormatValue.fromRawValue(raw) : null;
    // ML Kit takes exactly one packed plane: NV21 on Android, BGRA8888 on iOS.
    // Any other format means the controller was built with the wrong
    // `imageFormatGroup`, and guessing at the plane layout would feed it noise.
    if (format == null ||
        image.planes.length != 1 ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    return InputImage.fromBytes(
      bytes: image.planes.first.bytes,
      metadata: InputImageMetadata(
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFor({
    required int sensorOrientation,
    required DeviceOrientation deviceOrientation,
    required bool isFrontCamera,
  }) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensorOrientation);
    }
    final compensation = _rotationCompensation[deviceOrientation];
    if (compensation == null) return null;
    // The front camera is mirrored, so its compensation ADDS where the back
    // camera's subtracts. The scanner only ever uses the back camera, but the
    // sign is wrong-looking enough that getting it right here is cheaper than
    // debugging a mirrored box later.
    final degrees = isFrontCamera
        ? (sensorOrientation + compensation) % 360
        : (sensorOrientation - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(degrees);
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
/// widget tests, which have no platform channels) the scanner runs on the
/// no-op and behaves exactly as it did before live detection existed.
RegionDetector createRegionDetector() {
  if (kIsWeb) return const NoopRegionDetector();
  try {
    if (Platform.isAndroid || Platform.isIOS) return MlKitRegionDetector();
  } catch (_) {
    // Platform is unavailable in some test environments.
  }
  return const NoopRegionDetector();
}
