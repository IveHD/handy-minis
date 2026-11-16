#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/swift-toolchain.sh
xcrun swiftc -O -whole-module-optimization -module-cache-path "$swift_cache" \
  ${clang_flags[@]+"${clang_flags[@]}"} scripts/render-icons.swift -o .build/render-handyminis-icons
.build/render-handyminis-icons
