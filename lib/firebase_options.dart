// PLACEHOLDER — replace by running the FlutterFire CLI:
//
//   firebase login --reauth
//   flutterfire configure --project=matheasy-873e2
//
// That command regenerates THIS file with your project's real values and
// downloads the native config (android/app/google-services.json and
// ios/Runner/GoogleService-Info.plist). Until then the values below are
// structurally valid but not real, so the app still compiles and boots (Guest
// mode works fully); Google/Apple sign-in activate once the real config lands.
//
// See SETUP_FIREBASE.md for the full checklist.
//
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform — '
          'run `flutterfire configure --project=matheasy-873e2`.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'matheasy-873e2',
    authDomain: 'matheasy-873e2.firebaseapp.com',
    storageBucket: 'matheasy-873e2.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'matheasy-873e2',
    storageBucket: 'matheasy-873e2.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_WITH_FLUTTERFIRE_CONFIGURE',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: 'matheasy-873e2',
    storageBucket: 'matheasy-873e2.appspot.com',
    iosBundleId: 'com.matheasy.matheasy',
  );
}
