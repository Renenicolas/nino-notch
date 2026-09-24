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

# Stable signature so macOS permission grants (Accessibility, Calendar, Camera)
# survive rebuilds; ad-hoc signing mints a new identity every build and silently
# resets them. No entitlements: the app runs unsandboxed, as the unsigned build
# always did. Needs the "Nino Code Signing" keychain unlocked (see ~/dev/VoiceInk
# Makefile `make sign`); otherwise the build stays ad-hoc and says so.
KC="$HOME/Library/Keychains/nino-signing.keychain-db"
APP=build/DerivedData/Build/Products/Release/NinoNotch.app
# perl alarm: a locked keychain pops a password dialog and codesign waits forever.
if [ -f "$KC" ] && perl -e 'alarm 20; exec @ARGV' codesign --force --deep --keychain "$KC" --sign "Nino Code Signing" "$APP" 2>/dev/null; then
  codesign -dvv "$APP" 2>&1 | grep -E "^Authority=" | head -1
else
  codesign --force --deep --sign - "$APP" 2>/dev/null
  echo "note: signed ad-hoc (Nino Code Signing keychain missing or locked)"
fi
