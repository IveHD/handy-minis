#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
clang -fobjc-arc -O2 -Wall -I Sources/HandyMinis \
  Tests/ReleaseFeatures.m Sources/HandyMinis/QueuePanel.m Sources/HandyMinis/Analytics.m \
  Sources/HandyMinis/ClipboardStore.m Sources/HandyMinis/AccessibilityTrust.m \
  Sources/HandyMinis/Theme.m Sources/HandyMinis/TextActions.m Sources/HandyMinis/WindowTiling.m \
  -framework Cocoa -framework QuartzCore -framework ApplicationServices -framework ImageIO \
  -o .build/tests/release-features
.build/tests/release-features "$PWD/.build/tests/release"
