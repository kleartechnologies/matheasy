// Generates the official Matheasy app-icon and launch-screen assets for iOS and
// Android from the exact same [MatheasyMarkPainter] the in-app logo paints, so
// the shipped icon can never drift from the brand mark: a white M on a flat
// Emerald tile.
//
// Every proportion is read off [MatheasyAppIcon] — this file defines none of its
// own. The widget is the spec; this is only the rasterizer.
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

/// Android's adaptive canvas is 108dp but only the centre 72dp survives every
/// launcher mask, so the mark is [MatheasyAppIcon.markFraction] of *that* — not
/// of the full canvas.
const double kAdaptiveMarkFraction = MatheasyAppIcon.markFraction * 72 / 108;

/// Launch-screen mark edge, in points/dp. The mark is the only thing on the
/// splash, so it is sized well above the icon's 60pt but stays a mark on a
/// background — not a full-bleed logo.
const int kLaunchMarkPt = 96;

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
/// channel (App Store Connect rejects transparency). The tile is fully opaque,
/// so a downstream step drops the alpha to produce an RGB PNG.
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

/// The tile fill — flat [AppColors.primary]. The logo's own background measures
/// #06AD62 -> #06AB5F corner to corner, i.e. the identity does not gradient its
/// emerald; the tile is the one place the 2.97:1 tone is correct (WCAG 1.4.11
/// exempts logotypes).
Paint _tilePaint() => Paint()..color = AppColors.primary;

/// Full opaque square (iOS masks its own corners — no alpha allowed).
void _drawSquare(Canvas canvas, double size) {
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), _tilePaint());
  _paintMark(canvas, size, MatheasyAppIcon.markFraction);
}

/// Rounded-square tile on transparent (Android legacy launcher fallback).
void _drawRounded(Canvas canvas, double size) {
  final rrect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, size, size),
    Radius.circular(size * MatheasyAppIcon.radiusFraction),
  );
  canvas.drawRRect(rrect, _tilePaint());
  _paintMark(canvas, size, MatheasyAppIcon.markFraction);
}

/// White mark on transparent, sized for the Android adaptive safe zone. Doubles
/// as the `<monochrome>` layer, which is why the mark must stay single-tone: a
/// receding second tone reads as a ghost once the launcher tints this.
void _drawAdaptiveForeground(Canvas canvas, double size) {
  _paintMark(canvas, size, kAdaptiveMarkFraction);
}

/// The launch mark on transparent — the splash paints it over the brand
/// background, so only the mark is rasterized.
void Function(Canvas, double) _drawLaunchMark(Color color) {
  return (canvas, size) => _paintMark(canvas, size, 1, color: color);
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
      final bytes = await _renderRawRgba(entry.value, _drawSquare);
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
      final px = kLaunchMarkPt * entry.value;
      await _write(
        '$root/$launchDir/${entry.key}',
        await _renderPng(px, _drawLaunchMark(AppColors.primary)),
      );
      await _write(
        '$root/$launchDir/${entry.key.replaceFirst('LaunchImage', 'LaunchImage-Dark')}',
        await _renderPng(px, _drawLaunchMark(AppColors.primaryLight)),
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
      final bytes = await _renderPng(entry.value, _drawRounded);
      await _write('$root/$androidRes/${entry.key}/ic_launcher.png', bytes);
    }

    // ---- Android adaptive foreground (108dp canvas) ----
    const adaptiveDensities = <String, int>{
      'mipmap-mdpi': 108,
      'mipmap-hdpi': 162,
      'mipmap-xhdpi': 216,
      'mipmap-xxhdpi': 324,
      'mipmap-xxxhdpi': 432,
    };
    for (final entry in adaptiveDensities.entries) {
      final bytes = await _renderPng(entry.value, _drawAdaptiveForeground);
      await _write(
        '$root/$androidRes/${entry.key}/ic_launcher_foreground.png',
        bytes,
      );
    }

    // ---- Android launch mark (one raster per density) ----
    // Emitted in the identity emerald so the untinted drawable is already
    // correct on the light background; `launch_background.xml` re-tints it to
    // @color/launch_mark, which flips to the dark-surface emerald at night.
    const launchDensities = <String, double>{
      'mipmap-mdpi': 1,
      'mipmap-hdpi': 1.5,
      'mipmap-xhdpi': 2,
      'mipmap-xxhdpi': 3,
      'mipmap-xxxhdpi': 4,
    };
    for (final entry in launchDensities.entries) {
      final bytes = await _renderPng(
        (kLaunchMarkPt * entry.value).round(),
        _drawLaunchMark(AppColors.primary),
      );
      await _write('$root/$androidRes/${entry.key}/launch_image.png', bytes);
    }

    // ---- Play Store 512 icon (rounded, for store listing) ----
    final play = await _renderPng(512, _drawRounded);
    await _write('$root/android/app/src/main/ic_launcher-playstore.png', play);
  });
}
