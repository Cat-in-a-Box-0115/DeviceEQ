#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/build.noindex"
xcrun swiftc "$ROOT/Sources/App/BrandMark.swift" "$ROOT/Scripts/GenerateIcon.swift" -o "$ROOT/build.noindex/generate-icon"
"$ROOT/build.noindex/generate-icon" "$ROOT/build.noindex/DeviceEQ.iconset"
iconutil -c icns "$ROOT/build.noindex/DeviceEQ.iconset" -o "$ROOT/Assets/DeviceEQ.icns"
cp "$ROOT/build.noindex/DeviceEQ.iconset/icon_512x512@2x.png" "$ROOT/Assets/DeviceEQ-icon.png"
