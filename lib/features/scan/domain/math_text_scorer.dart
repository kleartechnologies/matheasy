import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'detected_region.dart';

/// One block of text the on-device reader found, reduced to the only two things
/// this layer needs: what characters were seen, and where they sat.
///
/// A plain value type rather than ML Kit's `TextBlock` so the scoring logic is
/// testable without a camera, a device, or the plugin — and so swapping the
/// on-device reader later touches one adapter instead of this whole file.
@immutable
class DetectedTextBlock {
  const DetectedTextBlock({required this.text, required this.bounds});

  final String text;

  /// In SOURCE IMAGE pixels — normalisation happens in [regionFromBlocks],
  /// which is the only place that knows the frame size.
  final Rect bounds;
}

/// Characters that make a relational claim. Their presence is the single
/// strongest signal that a line is maths rather than prose — a sentence almost
/// never contains a bare `=`.
const String _relational = '=≠<>≤≥≈≡';

/// Characters that combine quantities.
const String _arithmetic = '+×÷*/^√∫∑∏±';

/// Characters that only really appear in mathematical notation.
const String _notation = '√∫∑∏πθΔλμσΩ∞°′″';

/// How strongly [text] reads as mathematics rather than prose, `0..1`.
///
/// Deliberately a heuristic over CHARACTER CLASSES, not a parse. It is fed by
/// an on-device line-text reader whose output for real maths is partly mangled
/// by construction (a fraction arrives as two lines, an exponent loses its
/// superscript), so any attempt to parse it would be reasoning about a reading
/// that is known to be lossy. What survives that mangling is the *alphabet*:
/// digits, operators and short tokens survive even when the layout does not.
///
/// The score never gates a scan. It chooses what the live box says, and being
/// wrong costs a label, never an answer.
double mathScoreFor(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return 0;

  var digits = 0;
  var letters = 0;
  var relational = 0;
  var arithmetic = 0;
  var notation = 0;

  for (final rune in trimmed.runes) {
    final ch = String.fromCharCode(rune);
    if (RegExp(r'[0-9]').hasMatch(ch)) {
      digits++;
    } else if (RegExp(r'[a-zA-Z]').hasMatch(ch)) {
      letters++;
    }
    if (_relational.contains(ch)) relational++;
    if (_arithmetic.contains(ch)) arithmetic++;
    if (_notation.contains(ch)) notation++;
  }

  final significant = digits + letters;
  if (significant == 0 && relational + arithmetic + notation == 0) return 0;

  var score = 0.0;
  if (relational > 0) score += 0.35;
  if (arithmetic > 0) score += 0.25;
  if (notation > 0) score += 0.15;

  // Density of digits among the meaningful characters. Prose has a few; an
  // equation is mostly them.
  if (significant > 0) {
    score += 0.20 * math.min(1.0, digits / significant * 2);
  }

  // Token shape. Maths is written in very short tokens (`2x`, `=`, `13`);
  // prose is written in words. A long mean token length is the clearest
  // "this is a sentence" signal available without understanding the language,
  // so it SUBTRACTS rather than merely failing to add — otherwise a wordy
  // problem statement containing one number scores like an equation.
  final tokens = trimmed.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (tokens.isNotEmpty) {
    final meanLength =
        tokens.map((t) => t.length).reduce((a, b) => a + b) / tokens.length;
    if (meanLength <= 3) {
      score += 0.15;
    } else if (meanLength >= 6) {
      score -= 0.20;
    }
  }

  return score.clamp(0.0, 1.0);
}

/// Fold the on-device reader's [blocks] into a single [DetectedRegion] over a
/// frame of [imageSize].
///
/// The union is taken over the blocks that actually look like maths, not over
/// everything on the page — on a worksheet, including the header and the page
/// number would stretch the box to the full sheet and make the whole feature
/// pointless. When nothing scores as maths but text WAS found, it falls back to
/// the union of all blocks: something is better than nothing to frame, and the
/// score is reported honestly so the caller can label it "text" rather than
/// "maths".
DetectedRegion regionFromBlocks(
  List<DetectedTextBlock> blocks,
  Size imageSize, {
  double threshold = DetectedRegion.kMathScoreThreshold,
}) {
  if (blocks.isEmpty || imageSize.isEmpty) return DetectedRegion.none;

  final scored = [
    for (final block in blocks) (block: block, score: mathScoreFor(block.text)),
  ];
  final mathy = scored.where((s) => s.score >= threshold).toList();
  final chosen = mathy.isNotEmpty ? mathy : scored;
  if (chosen.isEmpty) return DetectedRegion.none;

  var union = chosen.first.block.bounds;
  for (final entry in chosen.skip(1)) {
    union = union.expandToInclude(entry.block.bounds);
  }

  // The region's score is the BEST block's, not the mean: one clean `2x+5=13`
  // among surrounding prose is a maths problem, and averaging would bury it.
  final best = chosen.map((s) => s.score).reduce(math.max);

  // A figure usually shows up as text blocks (its labels) separated from the
  // problem by a gap far wider than a line of prose ever is. Checked over ALL
  // the blocks, not the maths-looking ones: "5 cm" against the side of a
  // triangle is exactly the kind of block that fails the maths score, so
  // looking only at the chosen set would blind this to the very labels that
  // announce a figure. Advisory either way — it only widens the crop, so a
  // false positive costs a few pixels of margin.
  final hasDiagram = _looksLikeFigureLayout(blocks);

  return DetectedRegion(
    bounds: Rect.fromLTRB(
      (union.left / imageSize.width).clamp(0.0, 1.0),
      (union.top / imageSize.height).clamp(0.0, 1.0),
      (union.right / imageSize.width).clamp(0.0, 1.0),
      (union.bottom / imageSize.height).clamp(0.0, 1.0),
    ),
    blockCount: blocks.length,
    mathScore: best,
    hasDiagram: hasDiagram,
  );
}

/// Whether the blocks sit in two horizontally-separated clusters — the shape a
/// problem with a figure beside it makes.
bool _looksLikeFigureLayout(List<DetectedTextBlock> blocks) {
  if (blocks.length < 3) return false;
  final centers = blocks.map((b) => b.bounds.center.dx).toList()..sort();
  final span = centers.last - centers.first;
  if (span <= 0) return false;
  for (var i = 1; i < centers.length; i++) {
    // A gap wider than a third of the whole spread is a column break, not the
    // spacing between words on one line.
    if ((centers[i] - centers[i - 1]) > span / 3) return true;
  }
  return false;
}

/// Expand [region] into the rectangle that should actually be cropped.
///
/// Three things happen here, and each exists because of a way a tight crop
/// silently breaks a solve:
///
///   • **Padding** — a box drawn exactly on the glyphs clips descenders, the
///     tail of an integral sign, and the bar of a fraction. The margin is
///     proportional to the region, so it scales with how far away the page is.
///   • **A diagram widens it** — a figure's labels are text, but the figure
///     itself is not, so the reader never sees the lines it is made of. Cropping
///     to the labels alone would send the server a problem whose picture has
///     been cut away.
///   • **A floor on size** — a region far smaller than the frame is more likely
///     a misdetection than a genuinely tiny problem, and cropping hard to it
///     would throw away the page. Below the floor the crop widens toward the
///     centre rather than trusting the box.
///
/// Returns normalised coordinates, clamped inside the frame.
Rect cropRectFor(
  DetectedRegion region, {
  double padding = 0.04,
  double minSide = 0.25,
}) {
  if (region.isEmpty) return const Rect.fromLTRB(0, 0, 1, 1);

  final bounds = region.bounds;
  // A figure sits beside or below its text; give it room on every side.
  final margin = region.hasDiagram ? padding * 2.5 : padding;

  var left = bounds.left - margin;
  var top = bounds.top - margin;
  var right = bounds.right + margin;
  var bottom = bounds.bottom + margin;

  // Grow around the centre until each side clears the floor.
  final width = right - left;
  if (width < minSide) {
    final grow = (minSide - width) / 2;
    left -= grow;
    right += grow;
  }
  final height = bottom - top;
  if (height < minSide) {
    final grow = (minSide - height) / 2;
    top -= grow;
    bottom += grow;
  }

  return Rect.fromLTRB(
    left.clamp(0.0, 1.0),
    top.clamp(0.0, 1.0),
    right.clamp(0.0, 1.0),
    bottom.clamp(0.0, 1.0),
  );
}
