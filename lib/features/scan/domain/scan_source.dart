/// Where a scanned problem came from.
enum ScanSource {
  /// Live camera capture (the shutter).
  camera,

  /// Picked from the photo library.
  gallery,

  /// Typed in manually.
  manual,
}
