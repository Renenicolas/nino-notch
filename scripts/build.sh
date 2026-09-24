#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
xcodebuild \
  -project boringNotch.xcodeproj \
  -scheme boringNotch \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY=- \
  MACOSX_DEPLOYMENT_TARGET=14.0 \
  build

# Stable signature so macOS permission grants (Accessibility, Spotify automation,
# Calendar, Camera) survive rebuilds; ad-hoc signing mints a new identity every
# build and silently resets them. No entitlements: the app runs unsandboxed.
#
# Identity "Nino Notch Signing" (Nino Notch only; Nino Voice keeps its own) lives in
# ~/Library/Keychains/nino-notch-signing.keychain-db. Its password is NOT in this
# repo: it is read at build time from the login keychain item
#   service com.meetnino.notch.signing-keychain, account nino-notch-signing
# so it can never drift from what actually unlocks the keychain.
KC="$HOME/Library/Keychains/nino-notch-signing.keychain-db"
IDENTITY=812B9C3B71E6C0AA833C0A6149176D345CD7DBD8   # SHA-1 of "Nino Notch Signing"
APP=build/DerivedData/Build/Products/Release/NinoNotch.app
signed=0
if [ -f "$KC" ] && KCPW=$(security find-generic-password -s com.meetnino.notch.signing-keychain -a nino-notch-signing -w 2>/dev/null); then
  security unlock-keychain -p "$KCPW" "$KC" && \
  # perl alarm: never hang on a keychain dialog
  perl -e 'alarm 25; exec @ARGV' codesign --force --deep --keychain "$KC" --sign "$IDENTITY" "$APP" && signed=1
  unset KCPW
fi
if [ "$signed" = 1 ]; then
  codesign -dvv "$APP" 2>&1 | grep -E "^Authority=" | head -1
else
  codesign --force --deep --sign - "$APP" 2>/dev/null
  echo "note: signed AD-HOC (Nino Notch Signing keychain or its login-keychain password missing)"
fi
