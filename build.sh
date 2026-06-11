#!/bin/bash
# Build Snoopy.app — a menu bar app that plays sounds when the MacBook lid opens/closes.
set -euo pipefail
cd "$(dirname "$0")"

APP=Snoopy.app

echo "==> Building release binary"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Snoopy "$APP/Contents/MacOS/Snoopy"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sounds/*.wav "$APP/Contents/Resources/"

echo "==> Code signing (ad-hoc)"
codesign --force --sign - "$APP"

echo "==> Done: $(pwd)/$APP"
echo "    Run it with:  open $APP"
echo "    Install it:   cp -r $APP /Applications/"
