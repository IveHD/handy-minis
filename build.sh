#!/bin/bash
# Build the menu-bar clipboard queue as ClipStack.app.
set -euo pipefail
cd "$(dirname "$0")"

APP=".build/ClipStack.app"
SDK="$(xcrun --show-sdk-path)"
SPARKLE="$PWD/.build/sparkle"
if [[ ! -d "$SPARKLE/Sparkle.framework" ]]; then
  echo "请先执行 scripts/setup-sparkle.sh" >&2
  exit 1
fi
EXPLICIT_SIGN_ID="${SIGN_ID:-}"
SIGN_ID="${SIGN_ID:-ClipStack Codesign}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

clang \
  -fobjc-arc \
  -O2 \
  -Wall \
  -isysroot "$SDK" \
  -arch x86_64 -arch arm64 \
  -mmacosx-version-min=14.0 \
  -F "$SPARKLE" -framework Sparkle \
  -Wl,-rpath,@executable_path/../Frameworks \
  -framework Cocoa \
  -framework Carbon \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -o "$APP/Contents/MacOS/ClipStack" \
  Sources/ClipStack/*.m

cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
python3 scripts/configure-build.py "$APP/Contents/Info.plist"
if security find-identity -p codesigning -v | grep -q "$SIGN_ID"; then
  codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null
else
  if [[ -n "$EXPLICIT_SIGN_ID" ]]; then
    echo "无法访问指定签名身份 $SIGN_ID，请检查钥匙串与构建权限。" >&2
    exit 1
  fi
  echo "警告：未找到 ClipStack Codesign，使用临时签名；重新构建可能需要重新授权辅助功能。" >&2
  codesign --force --deep --sign - "$APP" >/dev/null
fi

rm -rf ClipStack.app
mv "$APP" ClipStack.app
APP="ClipStack.app"
echo "已生成 $APP"
echo "运行: open $APP"
echo "快捷键: ⌘⇧C"

if [[ "${1:-}" == "run" ]]; then
  open "$APP"
fi
