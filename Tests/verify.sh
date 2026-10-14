#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
mkdir -p build.noindex
clang++ -std=c++17 -O2 Sources/DSP/DSP.cpp Tests/DSP/DSPTests.cpp -o build.noindex/dsp-tests
build.noindex/dsp-tests
clang++ -std=c++17 -O2 Tests/DSP/StabilityTests.cpp -o build.noindex/stability-tests
build.noindex/stability-tests
xcrun swiftc Sources/App/APO.swift Tests/DSP/APOTests.swift -o build.noindex/apo-tests
build.noindex/apo-tests
xcrun swiftc -swift-version 5 -import-objc-header Sources/Audio/AudioBridge.h Sources/App/Models.swift Sources/App/APO.swift Sources/App/EQState.swift Sources/App/EQDisplayCache.swift Sources/App/Verification.swift Sources/App/Settings.swift Sources/App/SetupGuide.swift Sources/App/BrandMark.swift Tests/App/ModelTests.swift build.noindex/DSP.o build.noindex/AudioBridge.o -Xlinker -lc++ -framework SwiftUI -framework AppKit -framework CoreAudio -framework Foundation -framework ServiceManagement -o build.noindex/model-tests
build.noindex/model-tests
codesign --verify --deep --strict build.noindex/DeviceEQ.app
echo 'DSP, stability, parser and bundle checks passed. No live audio or permission requests.'
