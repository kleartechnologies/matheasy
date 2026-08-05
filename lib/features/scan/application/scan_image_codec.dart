import 'dart:convert';

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

/// Rotates a scan 90° clockwise and re-encodes it as JPEG at full resolution.
///
/// Pure and isolate-safe — call it through `compute`. The EXIF orientation is
/// baked before rotating so the flag can't re-apply on top of the rotated
/// pixels after re-encode. Falls back to the input bytes if the image can't be
/// decoded, so a rotate can never lose the capture.
///
/// Deliberately does NOT downscale to [kScanMaxSide]: rotation happens on the
/// crop screen, before the crop, and shrinking the source here would cost the
/// crop its resolution. The crop result is bounded on its own way out.
Uint8List rotateScanJpeg(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);
    final rotated = img.copyRotate(oriented, angle: 90);
    return Uint8List.fromList(
        img.encodeJpg(rotated, quality: kScanJpegQuality));
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
