// Generates the official Matheasy app-icon assets for iOS and Android by
// compositing the shipped brand render — the official logo the design team
// produced: a white M with a deep-forest outline and the signature long shadow
// on a flat Emerald field (brand/matheasy-app-icon-source.png).
//
// This is the ICON. It is deliberately RICHER than the in-app [MatheasyMark]
// (a flat, recolorable vector that has to survive 24px and dark mode). The
// brand system (docs PART 06) intends exactly this split: the icon carries the
// 3D outline + long shadow; the in-app mark stays flat. So — unlike the earlier
// revision — the shipped icon is no longer the same vector as the in-app mark;
// it is the rendered artwork, resized. The launch-screen marks below are still
// the flat vector (the splash recolors for light/dark, which a green-field
// raster cannot).
//
// Run with:  flutter test tool/generate_app_icons.dart
//            python3 tool/strip_alpha.py     # iOS icons must ship alpha-free
//
// It is deliberately placed under tool/ (not test/) so it does NOT run as part
// of the normal `flutter test` suite — it writes binary assets into ios/ and
// android/ and should only be invoked intentionally.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/brand/matheasy_app_icon.dart';
import 'package:matheasy/core/brand/matheasy_mark.dart';
import 'package:matheasy/core/theme/app_colors.dart';

/// The official rendered icon artwork (1080² flat-emerald field, opaque RGB).
/// Every icon raster below is a resample of this single source.
const String kIconSource = 'brand/matheasy-app-icon-source.png';

/// Android's adaptive canvas is 108dp but only the centre 72dp survives every
/// launcher mask, so the mark is [MatheasyAppIcon.markFraction] of *that* — not
/// of the full canvas. Used only for the `<monochrome>` silhouette below.
const double kAdaptiveMarkFraction = MatheasyAppIcon.markFraction * 72 / 108;

/// The rendered artwork occupies this fraction of the adaptive canvas. The M
/// inside the artwork spans ≈66% of it, so at 0.76 the M lands at ≈0.50 of the
/// canvas — comfortably inside the 72dp/108dp safe circle every launcher mask
/// keeps. The transparent margin lets the flat-emerald `<background>` bleed to
/// the edges; the artwork's own field measures #06AC60 corner-to-corner, so the
/// seam against [AppColors.primary] is invisible.
const double kAdaptiveIconFraction = 0.76;

/// Launch-screen TILE edge, in points/dp. The pre-boot splash now shows the same
/// rounded artwork tile as the icon (not a bare mark), centred on the brand
/// background. 120pt so the M inside the tile reads well; the iOS storyboard's
/// `<image>` intrinsic size and the Android mipmap densities are generated to
/// match, and the Android `<bitmap>` tint is removed so the tile keeps its
/// colours.
const int kLaunchTilePt = 120;

Future<ui.Image> _loadImage(String relPath) async {
  final bytes = await File(relPath).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<Uint8List> _renderPng(
  int px,
  void Function(Canvas canvas, double size) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas, px.toDouble());
  final picture = recorder.endRecording();
  final image = await picture.toImage(px, px);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Renders raw RGBA bytes — used for iOS icons, which must ship WITHOUT an alpha
/// channel (App Store Connect rejects transparency). The artwork is fully
/// opaque, so a downstream step drops the alpha to produce an RGB PNG.
Future<Uint8List> _renderRawRgba(
  int px,
  void Function(Canvas canvas, double size) draw,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  draw(canvas, px.toDouble());
  final picture = recorder.endRecording();
  final image = await picture.toImage(px, px);
  final data = await image.toByteData();
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// High-quality resample of the whole source artwork into [dst].
final Paint _imagePaint = Paint()
  ..filterQuality = FilterQuality.high
  ..isAntiAlias = true;

Rect _srcRect(ui.Image src) =>
    Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble());

void _paintMark(
  Canvas canvas,
  double size,
  double fraction, {
  Color color = AppColors.white,
}) {
  final mark = size * fraction;
  final offset = (size - mark) / 2;
  canvas.save();
  canvas.translate(offset, offset);
  MatheasyMarkPainter(color: color).paint(canvas, Size(mark, mark));
  canvas.restore();
}

/// Full opaque square of the artwork (iOS masks its own corners — no alpha
/// allowed, and the field is opaque edge-to-edge).
void _drawSquare(Canvas canvas, double size, ui.Image src) {
  canvas.drawImageRect(
    src,
    _srcRect(src),
    Rect.fromLTWH(0, 0, size, size),
    _imagePaint,
  );
}

/// Rounded-square artwork on transparent (Android legacy launcher fallback +
/// Play Store listing). iOS never uses this — it masks the square itself.
void _drawRounded(Canvas canvas, double size, ui.Image src) {
  final rrect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, size, size),
    Radius.circular(size * MatheasyAppIcon.radiusFraction),
  );
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawImageRect(
    src,
    _srcRect(src),
    Rect.fromLTWH(0, 0, size, size),
    _imagePaint,
  );
  canvas.restore();
}

/// The full artwork, inset to the adaptive safe zone on a transparent canvas.
/// The `<background>` emerald bleeds through the margin (the field green matches
/// it), so the launcher composites a seamless emerald icon with the M + shadow
/// safely inside every mask.
void _drawAdaptiveForeground(Canvas canvas, double size, ui.Image src) {
  final inset = size * (1 - kAdaptiveIconFraction) / 2;
  final edge = size * kAdaptiveIconFraction;
  canvas.drawImageRect(
    src,
    _srcRect(src),
    Rect.fromLTWH(inset, inset, edge, edge),
    _imagePaint,
  );
}

/// A single-tone M silhouette on transparent, sized for the safe zone — the
/// `<monochrome>` layer for Android 13+ themed icons. It MUST stay the flat
/// mark: the launcher tints this by its alpha, so the rendered artwork (a green
/// field) would theme to a solid blob. The colour here is irrelevant (only the
/// alpha shape is used); white matches the untinted preview.
void _drawMonochrome(Canvas canvas, double size) {
  _paintMark(canvas, size, kAdaptiveMarkFraction);
}

Future<void> _write(String path, Uint8List bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  // ignore: avoid_print
  print('  wrote $path (${bytes.length} bytes)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate iOS + Android app icons and launch marks', () async {
    final root = Directory.current.path;
    final src = await _loadImage('$root/$kIconSource');
    // ignore: avoid_print
    print('source: $kIconSource (${src.width}×${src.height})');

    // ---- iOS: opaque square, every size in the appiconset ----
    const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    const iosIcons = <String, int>{
      'Icon-App-20x20@1x.png': 20,
      'Icon-App-20x20@2x.png': 40,
      'Icon-App-20x20@3x.png': 60,
      'Icon-App-29x29@1x.png': 29,
      'Icon-App-29x29@2x.png': 58,
      'Icon-App-29x29@3x.png': 87,
      'Icon-App-40x40@1x.png': 40,
      'Icon-App-40x40@2x.png': 80,
      'Icon-App-40x40@3x.png': 120,
      'Icon-App-60x60@2x.png': 120,
      'Icon-App-60x60@3x.png': 180,
      'Icon-App-76x76@1x.png': 76,
      'Icon-App-76x76@2x.png': 152,
      'Icon-App-83.5x83.5@2x.png': 167,
      'Icon-App-1024x1024@1x.png': 1024,
    };
    // iOS icons are emitted as raw RGBA + a manifest; `tool/strip_alpha.py`
    // converts them into alpha-free RGB PNGs at the appiconset path.
    const rawDir = '.dart_tool/icon_rgba';
    final manifest = StringBuffer();
    for (final entry in iosIcons.entries) {
      final bytes =
          await _renderRawRgba(entry.value, (c, s) => _drawSquare(c, s, src));
      final rawName = '${entry.key}.rgba';
      await _write('$root/$rawDir/$rawName', bytes);
      manifest.writeln('$rawName ${entry.value} $iosDir/${entry.key}');
    }
    await _write(
      '$root/$rawDir/manifest.txt',
      Uint8List.fromList(manifest.toString().codeUnits),
    );

    // ---- iOS launch mark (keeps its alpha — only the AppIcon may not) ----
    // Light/dark variants: LaunchScreen.storyboard resolves them through the
    // imageset's luminosity appearances, the same way it resolves
    // @color/LaunchBackground.
    const launchDir = 'ios/Runner/Assets.xcassets/LaunchImage.imageset';
    const iosLaunch = <String, int>{
      'LaunchImage.png': 1,
      'LaunchImage@2x.png': 2,
      'LaunchImage@3x.png': 3,
    };
    for (final entry in iosLaunch.entries) {
      final px = kLaunchTilePt * entry.value;
      // The tile carries its own emerald field, so the light and dark
      // luminosity appearances are the SAME raster (theme-independent).
      final bytes = await _renderPng(px, (c, s) => _drawRounded(c, s, src));
      await _write('$root/$launchDir/${entry.key}', bytes);
      await _write(
        '$root/$launchDir/${entry.key.replaceFirst('LaunchImage', 'LaunchImage-Dark')}',
        bytes,
      );
    }

    // ---- Android legacy launcher (rounded tile) ----
    const androidRes = 'android/app/src/main/res';
    const legacyDensities = <String, int>{
      'mipmap-mdpi': 48,
      'mipmap-hdpi': 72,
      'mipmap-xhdpi': 96,
      'mipmap-xxhdpi': 144,
      'mipmap-xxxhdpi': 192,
    };
    for (final entry in legacyDensities.entries) {
      final bytes =
          await _renderPng(entry.value, (c, s) => _drawRounded(c, s, src));
      await _write('$root/$androidRes/${entry.key}/ic_launcher.png', bytes);
    }

    // ---- Android adaptive foreground (108dp canvas) — the full artwork ----
    const adaptiveDensities = <String, int>{
      'mipmap-mdpi': 108,
      'mipmap-hdpi': 162,
      'mipmap-xhdpi': 216,
      'mipmap-xxhdpi': 324,
      'mipmap-xxxhdpi': 432,
    };
    for (final entry in adaptiveDensities.entries) {
      final bytes = await _renderPng(
        entry.value,
        (c, s) => _drawAdaptiveForeground(c, s, src),
      );
      await _write(
        '$root/$androidRes/${entry.key}/ic_launcher_foreground.png',
        bytes,
      );
    }

    // ---- Android adaptive monochrome (108dp canvas) — the M silhouette ----
    // A separate layer now that the foreground is the rendered artwork: the
    // themed-icon tint must fall on the mark shape, not the green field.
    for (final entry in adaptiveDensities.entries) {
      final bytes = await _renderPng(entry.value, _drawMonochrome);
      await _write(
        '$root/$androidRes/${entry.key}/ic_launcher_monochrome.png',
        bytes,
      );
    }

    // ---- Android launch tile (one raster per density) ----
    // The rounded artwork tile, centred on the brand background by
    // launch_background.xml. The `<bitmap>` tint is REMOVED there so the tile
    // keeps its own colours (it is no longer a single-tone mark to re-tint).
    const launchDensities = <String, double>{
      'mipmap-mdpi': 1,
      'mipmap-hdpi': 1.5,
      'mipmap-xhdpi': 2,
      'mipmap-xxhdpi': 3,
      'mipmap-xxxhdpi': 4,
    };
    for (final entry in launchDensities.entries) {
      final bytes = await _renderPng(
        (kLaunchTilePt * entry.value).round(),
        (c, s) => _drawRounded(c, s, src),
      );
      await _write('$root/$androidRes/${entry.key}/launch_image.png', bytes);
    }

    // ---- Play Store 512 icon (rounded, for store listing) ----
    final play = await _renderPng(512, (c, s) => _drawRounded(c, s, src));
    await _write('$root/android/app/src/main/ic_launcher-playstore.png', play);
  });
}
