#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
BUILD="$ROOT/build.noindex"
APP="$BUILD/DeviceEQ.app"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
# ARCHS defaults to Apple Silicon. ARCHS="arm64 x86_64" builds a Universal app (Intel is not yet qualified).
ARCHS=${ARCHS:-arm64}
SLICES=()
for ARCH in $ARCHS; do
  clang++ -arch "$ARCH" -std=c++20 -O2 -mmacosx-version-min=14.2 -c "$ROOT/Sources/DSP/DSP.cpp" -o "$BUILD/DSP-$ARCH.o"
  clang++ -arch "$ARCH" -std=c++20 -O2 -fobjc-arc -mmacosx-version-min=14.2 -c "$ROOT/Sources/Audio/AudioBridge.mm" -o "$BUILD/AudioBridge-$ARCH.o"
  xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macosx14.2" -import-objc-header "$ROOT/Sources/Audio/AudioBridge.h" "$ROOT"/Sources/App/*.swift "$BUILD/DSP-$ARCH.o" "$BUILD/AudioBridge-$ARCH.o" -Xlinker -lc++ -framework SwiftUI -framework AppKit -framework CoreAudio -framework Foundation -framework ServiceManagement -framework Carbon -o "$BUILD/DeviceEQ-$ARCH"
  SLICES+=("$BUILD/DeviceEQ-$ARCH")
done
# Tests link the native-architecture objects under their historical names.
NATIVE=$(uname -m)
if [ -f "$BUILD/DSP-$NATIVE.o" ]; then cp "$BUILD/DSP-$NATIVE.o" "$BUILD/DSP.o"; cp "$BUILD/AudioBridge-$NATIVE.o" "$BUILD/AudioBridge.o"; fi
lipo -create "${SLICES[@]}" -output "$APP/Contents/MacOS/DeviceEQ"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>DeviceEQ</string><key>CFBundleIdentifier</key><string>org.deviceeq.app</string><key>CFBundleName</key><string>DeviceEQ</string><key>CFBundleDisplayName</key><string>DeviceEQ</string><key>CFBundleIconFile</key><string>DeviceEQ</string><key>CFBundleVersion</key><string>20</string><key>CFBundleShortVersionString</key><string>0.4.8</string><key>LSMinimumSystemVersion</key><string>14.2</string><key>NSAudioCaptureUsageDescription</key><string>DeviceEQ equalizes your selected sound outputs locally. Audio is never uploaded.</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/></dict></plist>
PLIST
clang++ $(for A in $ARCHS; do printf -- "-arch %s " "$A"; done) -std=c++20 -O2 -fobjc-arc -mmacosx-version-min=14.2 "$ROOT/Tests/Audio/tone_producer.mm" -framework Foundation -framework CoreAudio -framework AudioToolbox -o "$APP/Contents/Resources/route-tone"
SIGN_IDENTITY=${SIGN_IDENTITY:--}
SIGN_ARGS=(--force --sign "$SIGN_IDENTITY")
if [ "$SIGN_IDENTITY" != "-" ]; then SIGN_ARGS+=(--options runtime --timestamp); fi
codesign "${SIGN_ARGS[@]}" "$APP/Contents/Resources/route-tone"
cp "$ROOT/Assets/DeviceEQ.icns" "$APP/Contents/Resources/DeviceEQ.icns"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$ROOT/PRIVACY.md" "$APP/Contents/Resources/"
codesign "${SIGN_ARGS[@]}" "$APP"
printf 'Built %s\n' "$APP"
