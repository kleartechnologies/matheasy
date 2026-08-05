import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import '../../../core/monitoring/logging_service.dart';

/// The one enumeration of this device's cameras, shared by every scanner open.
///
/// `availableCameras()` is a platform-channel round trip that asks the OS to
/// describe hardware which cannot change while the app is running. Paying for
/// it in `initState` meant every visit to the scanner spent it again, in the
/// window where the user is staring at an empty viewfinder.
Future<List<CameraDescription>>? _cached;

/// The device's cameras, enumerated at most once per launch.
///
/// A FAILURE is not cached. Enumeration can fail transiently — the camera is
/// held by another app, the service is restarting — and remembering that
/// forever would turn one bad moment into a scanner that is broken until the
/// app is killed.
Future<List<CameraDescription>> cachedAvailableCameras() {
  final pending = _cached;
  if (pending != null) return pending;
  final started = availableCameras();
  _cached = started;
  return started.then((cameras) {
    // An empty list is a failure wearing a success's clothes — don't keep it.
    if (cameras.isEmpty) _cached = null;
    return cameras;
  }, onError: (Object error) {
    _cached = null;
    throw error;
  });
}

/// Enumerate ahead of time, so the first scanner open finds the answer waiting.
///
/// Best-effort and fire-and-forget: it is called after the first frame, and a
/// failure here changes nothing — [cachedAvailableCameras] simply tries again
/// when the scanner actually needs the list.
///
/// This only asks the OS what hardware exists. It opens no session and takes no
/// image, so it triggers no permission prompt and lights no camera indicator.
void warmCameraList() {
  unawaited(cachedAvailableCameras().then(
    (_) {},
    onError: (Object error) =>
        LoggingService.info('Camera pre-enumeration skipped: $error'),
  ));
}

@visibleForTesting
void resetCameraListCache() => _cached = null;
