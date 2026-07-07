// Generates the official Matheasy app-icon assets (Concept C) for iOS and
// Android from the exact same [MatheasyMarkPainter] used by the in-app logo, so
// the shipped icon can never drift from the brand mark.
//
// Run with:  flutter test tool/generate_app_icons.dart
//
// It is deliberately placed under tool/ (not test/) so it does NOT run as part
// of the normal `flutter test` suite — it writes binary assets into ios/ and
// android/ and should only be invoked intentionally.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matheasy/core/brand/matheasy_mark.dart';
import 'package:matheasy/core/theme/app_colors.dart';

/// Brand spec.
const double kRadiusFraction = 0.225; // rounded-square corner radius
const double kMarkFraction = 0.56; // mark size within a full tile
const double kAdaptiveMarkFraction = 0.38; // mark size within 108dp adaptive canvas

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
/// channel (App Store Connect rejects transparency). The Concept C tile is fully
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

void _paintMark(Canvas canvas, double size, double fraction) {
  final mark = size * fraction;
  final offset = (size - mark) / 2;
  canvas.save();
  canvas.translate(offset, offset);
  const MatheasyMarkPainter(color: AppColors.white)
      .paint(canvas, Size(mark, mark));
  canvas.restore();
}

/// Full opaque square (iOS masks its own corners — no alpha allowed).
void _drawSquare(Canvas canvas, double size) {
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size, size),
    Paint()..color = AppColors.primary,
  );
  _paintMark(canvas, size, kMarkFraction);
}

/// Rounded-square tile on transparent (Android legacy launcher fallback).
void _drawRounded(Canvas canvas, double size) {
  final rrect = RRect.fromRectAndRadius(
    Rect.fromLTWH(0, 0, size, size),
    Radius.circular(size * kRadiusFraction),
  );
  canvas.drawRRect(rrect, Paint()..color = AppColors.primary);
  _paintMark(canvas, size, kMarkFraction);
}

/// White mark on transparent, sized for the Android adaptive safe zone.
void _drawAdaptiveForeground(Canvas canvas, double size) {
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

  test('generate iOS + Android app icons from Concept C', () async {
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

    // ---- Play Store 512 icon (rounded, for store listing) ----
    final play = await _renderPng(512, _drawRounded);
    await _write('$root/android/app/src/main/ic_launcher-playstore.png', play);
  });
}
