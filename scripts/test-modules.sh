#!/bin/zsh
# Module contract check: source rules, compile, then RUN the checks.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
OUT=/tmp/nino-module-tests
rm -f "$OUT"

if grep -R -E -n 'URLSession|URLRequest|WKWebView|AVCapture|http://|https://' Nino/Stubs --include='*.swift'; then
  echo "FAIL: a stub file talks to the network or a capture device"; exit 1
fi
echo "ok  stubs contain no network or capture APIs"

for f in Nino/Stubs/*.swift; do
  grep -q 'let isStub = true' "$f" || { echo "FAIL: $f is not marked isStub = true"; exit 1; }
  grep -q 'TODO: wire real integration here' "$f" || { echo "FAIL: $f has no wire-in TODO"; exit 1; }
done
echo "ok  every stub is isStub = true and has a wire-in TODO"

# NinoModulePreview.swift needs app types (AppDelegate), so it is left out here.
"$SWIFTC" -sdk "$SDKROOT" -target arm64-apple-macosx14.0 -parse-as-library -emit-executable \
  $(ls Nino/*.swift | grep -v NinoModulePreview) Nino/Stubs/*.swift NinoTests/main.swift -o "$OUT"
echo "ok  module contract compiled ($OUT)"

# perl alarm = portable timeout; a hang is a failure, not a pass
perl -e 'alarm 120; exec @ARGV' "$OUT"
