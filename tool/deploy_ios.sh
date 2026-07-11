#!/usr/bin/env bash
#
# Deploy Matheasy to a connected iPhone in one command:
#
#     tool/deploy_ios.sh
#
# Why this exists: the project lives on the iCloud-synced Desktop, and iCloud
# stamps `com.apple.FinderInfo` onto build files. `codesign` refuses to sign
# anything carrying FinderInfo ("resource fork, Finder information, or similar
# detritus not allowed"), and iCloud re-stamps the .app faster than an in-place
# sign can finish — so every `flutter run` dies at the signing step.
#
# The fix: let Flutter assemble + entitle the app (its final sign fails on
# iCloud — expected), then copy the bundle to /tmp (a local disk iCloud can't
# touch), sign it there, and install with devicectl.
#
# The real cure is to move the project off iCloud (e.g. ~/Developer/), after
# which a plain `flutter run` works. Until then, use this.

set -uo pipefail

BUNDLE_ID="com.matheasy.matheasy"
STAGE="/tmp/matheasy_ios_deploy"
cd "$(dirname "$0")/.." || exit 1

say() { printf '\033[1;32m▸\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. pick the connected physical iOS device -----------------------------
UDID="$(flutter devices --machine 2>/dev/null | python3 -c '
import sys, json
try: devs = json.load(sys.stdin)
except Exception: devs = []
ios = [d for d in devs
       if str(d.get("targetPlatform","")).startswith("ios")
       and not d.get("emulator", True)]
print(ios[0]["id"] if ios else "")')"
[ -n "$UDID" ] || die "No physical iOS device found. Unlock your iPhone, trust this Mac, and retry."
say "Device: $UDID"

# --- 2. build a signed release. The project sits on iCloud, which re-stamps
#        com.apple.FinderInfo onto the native-asset frameworks — so the build's
#        own `install_code_assets` / framework codesign fails and the app never
#        finishes assembling. A tight background loop strips that xattr off the
#        codesign targets faster than iCloud re-adds it, so the build gets past
#        signing and assembles the full bundle. (We re-sign cleanly in step 4,
#        so it doesn't matter that this loop also clears the build's own sigs.)
say "Building release (stripping FinderInfo so the in-build codesign passes)…"
(
  END=$((SECONDS + 900))
  while [ $SECONDS -lt $END ]; do
    for d in build/ios/Release-iphoneos/Runner.app \
             build/ios/iphoneos/Runner.app \
             build/native_assets/ios; do
      [ -e "$d" ] && xattr -cr "$d" 2>/dev/null
    done
  done
) &
STRIP_PID=$!
disown "$STRIP_PID" 2>/dev/null || true   # keep bash from printing "Terminated" later
flutter build ios --release >/tmp/matheasy_build.log 2>&1
kill "$STRIP_PID" 2>/dev/null || true
APP=""
for cand in build/ios/iphoneos/Runner.app build/ios/Release-iphoneos/Runner.app; do
  [ -d "$cand" ] && APP="$cand"
done
[ -n "$APP" ] || { tail -25 /tmp/matheasy_build.log; die "App bundle not assembled — see /tmp/matheasy_build.log"; }
say "Assembled: $APP"

# --- 3. resolve signing identity + merged entitlements ---------------------
ID="$(security find-identity -v -p codesigning \
      | awk '/Apple Development|Apple Distribution/ {print $2; exit}')"
[ -n "$ID" ] || die "No codesigning identity in the login keychain."
XCENT="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
           -name 'Runner.app.xcent' -path '*Release-iphoneos*' -print0 2>/dev/null \
         | xargs -0 ls -t 2>/dev/null | head -1)"
say "Identity: $ID"
say "Entitlements: ${XCENT:-<none found — Sign in with Apple / push may not work>}"

# --- 4. stage to local disk (off iCloud) and sign there --------------------
say "Staging to $STAGE and signing (iCloud can't touch /tmp)…"
rm -rf "$STAGE" && mkdir -p "$STAGE"
ditto --noextattr --norsrc "$APP" "$STAGE/Runner.app"
xattr -cr "$STAGE/Runner.app"
for f in "$STAGE/Runner.app/Frameworks/"*; do
  [ -e "$f" ] || continue
  codesign --force --sign "$ID" --preserve-metadata=identifier,entitlements \
           --timestamp=none "$f" >/dev/null 2>&1 \
    || die "Failed to sign framework $(basename "$f")"
done
if [ -n "$XCENT" ]; then
  codesign --force --sign "$ID" --entitlements "$XCENT" \
           --timestamp=none --generate-entitlement-der "$STAGE/Runner.app" \
    || die "Failed to sign app bundle."
else
  codesign --force --sign "$ID" --timestamp=none \
           --generate-entitlement-der "$STAGE/Runner.app" \
    || die "Failed to sign app bundle."
fi
codesign --verify --strict "$STAGE/Runner.app" || die "Signature verification failed."
say "Signed & verified."

# --- 5. install + launch ---------------------------------------------------
say "Installing on device…"
xcrun devicectl device install app --device "$UDID" "$STAGE/Runner.app" 2>&1 \
  | grep -iE "App installed|bundleID|error" | sed 's/^/  /'
say "Launching…"
xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID" 2>&1 \
  | grep -iE "Launched|error" | sed 's/^/  /'
printf '\033[1;32m✅ Matheasy is on your iPhone.\033[0m\n'
