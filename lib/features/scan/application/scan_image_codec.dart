import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest-edge cap (px) applied to a cropped scan before upload.
const int kScanMaxSide = 1600;

/// JPEG quality (0–100) used when re-encoding a cropped scan.
const int kScanJpegQuality = 85;

/// A cropped JPEG at or under this size is uploaded as-is — `crop_your_image`
/// already emits a compact JPEG for JPEG input, so re-decoding + re-encoding it
/// (a second isolate round-trip) is wasted work and a needless quality pass.
/// Larger results (e.g. big gallery crops) still go through [encodeScanJpeg] to
/// be downscaled.
const int kScanDirectUploadMaxBytes = 1024 * 1024; // 1 MB

/// Whether [bytes] start with the JPEG SOI marker (`FF D8`). Used to confirm a
/// crop result is JPEG before uploading it directly under an `image/jpeg` label.
bool isJpegBytes(Uint8List bytes) =>
    bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;

/// Re-encodes cropped image [bytes] into a compact JPEG: downscaled so the
/// longest edge is at most [kScanMaxSide]px, at [kScanJpegQuality]. Keeps
/// uploads small and normalizes the format so the backend always receives JPEG.
///
/// Pure and isolate-safe — call it through `compute`. Falls back to the input
/// bytes if the image can't be decoded or re-encoded (some malformed inputs make
/// the decoder throw rather than return null), so this never propagates an
/// error into the crop flow.
Uint8List encodeScanJpeg(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final longest =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final resized = longest > kScanMaxSide
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? kScanMaxSide : null,
            height: decoded.height > decoded.width ? kScanMaxSide : null,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(resized, quality: kScanJpegQuality));
  } catch (_) {
    return bytes;
  }
}

/// Base64-encodes scan [bytes] for the `recognizeEquation` payload.
///
/// Pure and isolate-safe — call it through `compute`. This exists as its own
/// top-level function for exactly that reason: encoding a ~900KB JPEG produces a
/// ~1.2MB string, and building it synchronously on the UI isolate janks the
/// frames at the precise moment the user is watching for the app to respond to
/// their capture.
String encodeScanBase64(Uint8List bytes) => base64Encode(bytes);

/// A capture plus the normalised rectangle to cut out of it.
///
/// One argument because `compute` takes one. Immutable and made only of a byte
/// list and four doubles, so it crosses the isolate boundary cheaply.
@immutable
class ScanCropRequest {
  const ScanCropRequest(this.bytes, this.rect);

  final Uint8List bytes;

  /// Normalised `0..1` of the SOURCE image, origin top-left.
  final Rect rect;
}

/// Crops [request] to its normalised rectangle and returns a compact JPEG.
///
/// Pure and isolate-safe — call it through `compute`. Returns the input bytes
/// unchanged if the image can't be decoded, if the rectangle is degenerate, or
/// if anything throws: a scan that uploads the whole page still gets solved,
/// whereas a scan that fails here would be a capture the user has to repeat.
///
/// The orientation is BAKED before cropping. A phone camera stores its picture
/// in sensor order plus an EXIF rotation flag, but the rectangle arrives in
/// *display* coordinates — the space the detector and the user's own eyes see.
/// Cropping the unbaked pixels with a display-space rectangle would cut a
/// sideways rectangle out of the page and hand the server a slice of margin.
Uint8List cropScanJpeg(ScanCropRequest request) {
  final bytes = request.bytes;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);

    final rect = request.rect;
    final left = (rect.left * oriented.width).round().clamp(0, oriented.width);
    final top = (rect.top * oriented.height).round().clamp(0, oriented.height);
    final right = (rect.right * oriented.width).round().clamp(0, oriented.width);
    final bottom =
        (rect.bottom * oriented.height).round().clamp(0, oriented.height);
    final width = right - left;
    final height = bottom - top;
    // Guard against a detector that returned nonsense. Anything this small is a
    // misdetection, not a problem written very small, and cropping to it would
    // destroy the scan.
    if (width < 32 || height < 32) return encodeScanJpeg(bytes);

    final cropped = img.copyCrop(
      oriented,
      x: left,
      y: top,
      width: width,
      height: height,
    );
    final longest =
        cropped.width > cropped.height ? cropped.width : cropped.height;
    final resized = longest > kScanMaxSide
        ? img.copyResize(
            cropped,
            width: cropped.width >= cropped.height ? kScanMaxSide : null,
            height: cropped.height > cropped.width ? kScanMaxSide : null,
          )
        : cropped;
    return Uint8List.fromList(img.encodeJpg(resized, quality: kScanJpegQuality));
  } catch (_) {
    return bytes;
  }
}
