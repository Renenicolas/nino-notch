#!/bin/zsh
# Module contract: source rules, then run the checks INSIDE the built app
# (the live modules need app types, so there is no standalone test binary).
# Run scripts/build.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/DerivedData/Build/Products/Release/NinoNotch.app
RECEIPT=/tmp/nino-module-selftest.txt

if grep -R -E -n 'URLSession|URLRequest|WKWebView|AVCapture|http://|https://' Nino/Stubs --include='*.swift'; then
  echo "FAIL: a stub file talks to the network or a capture device"; exit 1
fi
echo "ok  stubs contain no network or capture APIs"

for f in Nino/Stubs/*.swift(N); do  # (N): no stubs left is fine
  grep -q 'let isStub = true' "$f" || { echo "FAIL: $f is not marked isStub = true"; exit 1; }
  grep -q 'TODO: wire real integration here' "$f" || { echo "FAIL: $f has no wire-in TODO"; exit 1; }
done
echo "ok  every stub is isStub = true and has a wire-in TODO"

# The contract itself checks that the old nino.vellum id is rejected, so skip it here.
if grep -R -i -n 'vellum' Nino README.md WIRE-IN.md | grep -v NinoModuleContract.swift; then
  echo "FAIL: Vellum is still mentioned"; exit 1
fi
echo "ok  no Vellum left in the app or docs"

[ -x "$APP/Contents/MacOS/NinoNotch" ] || { echo "FAIL: build first (scripts/build.sh)"; exit 1; }
rm -f "$RECEIPT"
# perl alarm = portable timeout; a hang is a failure, not a pass
perl -e 'alarm 60; exec @ARGV' "$APP/Contents/MacOS/NinoNotch" --nino-module-self-test >/dev/null 2>&1 || true
[ -f "$RECEIPT" ] || { echo "FAIL: self-test wrote no receipt"; exit 1; }
cat "$RECEIPT"
grep -q '^ALL TESTS PASSED$' "$RECEIPT"
