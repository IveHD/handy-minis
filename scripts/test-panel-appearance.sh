#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/tests
clang -fobjc-arc -O2 -Wall -I Sources/HandyMinis \
  Tests/PanelAppearance.m Sources/HandyMinis/Theme.m Sources/HandyMinis/SettingsPanel.m \
  -framework Cocoa -framework QuartzCore -framework Carbon -o .build/tests/panel-appearance
.build/tests/panel-appearance "$PWD/.build/tests/panel-appearance"

suite="test.HandyMinis.PanelAppearance.$(uuidgen)"
trap '.build/tests/panel-appearance --cleanup-preferences "$suite"' EXIT
.build/tests/panel-appearance --write-preferences "$suite"
.build/tests/panel-appearance --read-preferences "$suite"
