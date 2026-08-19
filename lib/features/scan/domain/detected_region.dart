import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Where the maths is on the page, and how confident the on-device reader is
/// that it IS maths.
///
/// The coordinates are NORMALISED (`0..1` of the source image's width/height,
/// origin top-left) so one region survives every space it has to cross: the
/// camera frame it was detected in, the preview widget it is drawn over, and
/// the full-resolution capture it is finally cropped out of. Those three have
/// different pixel sizes and, on a phone, different rotations.
///
/// Nothing here is a transcription. [DetectedRegion] answers "where" and
/// "roughly what kind", never "what does it say" — the maths itself is read
/// server-side by OpenAI Vision, and this type deliberately carries no field
/// that could be mistaken for a reading.
@immutable
class DetectedRegion {
  const DetectedRegion({
    required this.bounds,
    required this.blockCount,
    required this.mathScore,
    this.hasDiagram = false,
  });

  /// Nothing found in the frame.
  static const DetectedRegion none = DetectedRegion(
    bounds: Rect.zero,
    blockCount: 0,
    mathScore: 0,
  );

  /// The union of the text blocks that look like maths, normalised `0..1`.
  final Rect bounds;

  /// How many text blocks the reader found in the whole frame. A page with many
  /// blocks is a document (a worksheet, a textbook page) rather than a single
  /// problem, which changes how tightly it is safe to crop.
  final int blockCount;

  /// `0..1` — how strongly the characters read as mathematics rather than prose.
  /// Drives the live box's state, not the pipeline: a low score never blocks a
  /// scan, because being wrong about this must cost nothing.
  final double mathScore;

  /// Whether a figure appears to sit alongside the text — a wide gap in the
  /// block layout. Advisory only; it widens the crop so a diagram is never
  /// severed from the problem that references it.
  final bool hasDiagram;

  /// Whether anything worth framing was found.
  bool get isEmpty => blockCount == 0 || bounds.isEmpty;
  bool get isNotEmpty => !isEmpty;

  /// Whether this reads as maths confidently enough to tell the user so.
  bool get looksLikeMath => isNotEmpty && mathScore >= kMathScoreThreshold;

  /// The score at which the live box switches from "text found" to "maths
  /// found". Tuned to accept a bare `2x+5=13` while rejecting a paragraph of
  /// prose that happens to contain a page number.
  static const double kMathScoreThreshold = 0.35;

  @override
  bool operator ==(Object other) =>
      other is DetectedRegion &&
      other.bounds == bounds &&
      other.blockCount == blockCount &&
      other.mathScore == mathScore &&
      other.hasDiagram == hasDiagram;

  @override
  int get hashCode => Object.hash(bounds, blockCount, mathScore, hasDiagram);

  @override
  String toString() => 'DetectedRegion($bounds, blocks: $blockCount, '
      'math: ${mathScore.toStringAsFixed(2)})';
}
