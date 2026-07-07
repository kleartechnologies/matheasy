# Firebase Auth setup — Stage 7

All the app-side auth code, native wiring, and tests are done. The app **builds
and runs today** in guest-only mode against a placeholder config. To turn on
real Google / Apple sign-in against your Firebase project **`matheasy-873e2`**,
complete the steps below. They require your Google + Apple developer accounts,
so they can't be automated from here.

Nothing in `lib/` needs to change — `flutterfire configure` regenerates
`lib/firebase_options.dart` and drops the native config files, and the app
detects them automatically (Android applies the Google-Services plugin only when
`google-services.json` exists; bootstrap enables cloud auth once the real
`apiKey` is present).

## 1. Generate the config (required)

```bash
# The CLI session expired — sign in again (opens a browser):
firebase login --reauth

# Wire this repo to your project (overwrites lib/firebase_options.dart and
# downloads android/app/google-services.json + ios/Runner/GoogleService-Info.plist):
flutterfire configure --project=matheasy-873e2 --platforms=ios,android
```

## 2. Enable the sign-in providers (Firebase console)

Firebase Console → **Authentication → Sign-in method**:

- Enable **Google**.
- Enable **Apple** (paste the Service ID, Apple Team ID, Key ID, and private
  key from your Apple Developer account).

## 3. Android — Google Sign-In

Google Sign-In needs your app's signing certificate fingerprints so it can issue
ID tokens:

```bash
# debug fingerprint (repeat for your release keystore before shipping):
cd android && ./gradlew signingReport
```

Add the **SHA-1** (and SHA-256) to Firebase Console → Project settings → your
Android app, then re-run `flutterfire configure` so the updated
`google-services.json` includes the OAuth client.

## 4. iOS — capabilities & URL scheme

1. Open `ios/Runner.xcworkspace` in Xcode → Runner target → **Signing &
   Capabilities** → **+ Capability → Sign in with Apple**. (A ready-made
   `ios/Runner/Runner.entitlements` is already in the repo for Xcode to link.)
2. Google Sign-In needs the reversed client ID as a URL scheme. Open the
   downloaded `ios/Runner/GoogleService-Info.plist`, copy `REVERSED_CLIENT_ID`,
   and add it under **Info → URL Types** (or `CFBundleURLTypes`) for the Runner
   target.

## 5. Verify

```bash
flutter run                 # sign in with Google / Apple / Guest on a device
flutter analyze             # expect: No issues found!
flutter test                # expect: all tests pass
```

Guest mode works with or without any of the above.
