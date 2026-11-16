#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-toolchain.sh
if [[ ! -f docs/assets/app-icon.png ]]; then scripts/render-icons.sh; fi
scripts/test-clipboard-navigation.sh
scripts/test-release-features.sh
xcrun swiftc -O -whole-module-optimization -module-cache-path "$swift_cache" \
  ${clang_flags[@]+"${clang_flags[@]}"} scripts/render-demos.swift Sources/HandyMinis/Screenshot/*.swift -o .build/render-handyminis-demos
.build/render-handyminis-demos
