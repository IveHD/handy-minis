#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
clang -fobjc-arc -O2 -Wall -I Sources/HandyMinis \
  Tests/ClipboardNavigation.m Sources/HandyMinis/QueuePanel.m Sources/HandyMinis/Analytics.m \
  Sources/HandyMinis/ClipboardStore.m Sources/HandyMinis/AccessibilityTrust.m \
  Sources/HandyMinis/Theme.m Sources/HandyMinis/SettingsPanel.m Sources/HandyMinis/TextActions.m \
  -framework Cocoa -framework QuartzCore -framework ApplicationServices -framework ImageIO -framework Carbon \
  -o .build/tests/clipboard-navigation
.build/tests/clipboard-navigation "$PWD/.build/tests/clipboard"
