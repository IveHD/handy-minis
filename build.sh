#!/bin/bash
# Build the macOS toolbox as HandyMinis.app.
set -euo pipefail
cd "$(dirname "$0")"

APP=".build/HandyMinis.app"
SDK="$(xcrun --show-sdk-path)"
SPARKLE="$PWD/.build/sparkle"
if [[ ! -d "$SPARKLE/Sparkle.framework" ]]; then
  echo "请先执行 scripts/setup-sparkle.sh" >&2
  exit 1
fi
EXPLICIT_SIGN_ID="${SIGN_ID:-}"
SIGN_ID="${SIGN_ID:-ClipStack Codesign}"

rum_compile_flags=()
rum_link_flags=()
RUM_SDK="$PWD/.build/aliyun-rum/AlibabaCloud_RUM_macOS_0.4.4"
if [[ -n "${ALIYUN_RUM_APP_ID:-}" || -n "${ALIYUN_RUM_CONFIG_ADDRESS:-}" ]]; then
  : "${ALIYUN_RUM_APP_ID:?请同时设置 ALIYUN_RUM_APP_ID 和 ALIYUN_RUM_CONFIG_ADDRESS}"
  : "${ALIYUN_RUM_CONFIG_ADDRESS:?请同时设置 ALIYUN_RUM_APP_ID 和 ALIYUN_RUM_CONFIG_ADDRESS}"
  if [[ ! -f "$RUM_SDK/include/alibabacloud_rum.h" ]]; then
    echo "请先执行 scripts/setup-aliyun-rum.sh" >&2
    exit 1
  fi
  rum_compile_flags=(-DHANDYMINIS_ALIYUN_RUM -I "$RUM_SDK/include")
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

source scripts/swift-toolchain.sh

for arch in x86_64 arm64; do
  if [[ -n "${ALIYUN_RUM_APP_ID:-}" ]]; then
    rum_link_flags=("$RUM_SDK/lib/$arch/Release/libalibabacloud_rum.dylib")
  fi
  object_dir="$PWD/.build/handyminis-objects/$arch"
  mkdir -p "$object_dir"
  objects=()
  for source_file in Sources/HandyMinis/*.m; do
    object="$object_dir/$(basename "${source_file%.m}").o"
    clang -c -fobjc-arc -O2 -Wall -isysroot "$SDK" -arch "$arch" \
      ${rum_compile_flags[@]+"${rum_compile_flags[@]}"} \
      -mmacosx-version-min=14.0 -F "$SPARKLE" "$source_file" -o "$object"
    objects+=("$object")
  done

  xcrun swiftc -parse-as-library -O -whole-module-optimization \
    -sdk "$SDK" -target "$arch-apple-macosx14.0" -module-cache-path "$swift_cache" \
    ${clang_flags[@]+"${clang_flags[@]}"} \
    Sources/HandyMinis/ScreenshotBridge.swift Sources/HandyMinis/Screenshot/*.swift "${objects[@]}" \
    ${rum_link_flags[@]+"${rum_link_flags[@]}"} \
    -F "$SPARKLE" -framework Sparkle -framework QuartzCore -framework Carbon \
    -framework ApplicationServices -framework ServiceManagement \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$object_dir/HandyMinis"
done
xcrun lipo -create .build/handyminis-objects/{x86_64,arm64}/HandyMinis \
  -output "$APP/Contents/MacOS/HandyMinis"

cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/StatusIconTemplate*.png "$APP/Contents/Resources/"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
if [[ -n "${ALIYUN_RUM_APP_ID:-}" ]]; then
  for library in libalibabacloud_rum.dylib libcurl.dylib; do
    xcrun lipo -create "$RUM_SDK"/lib/{x86_64,arm64}/Release/"$library" \
      -output "$APP/Contents/Frameworks/$library"
  done
fi
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

rm -rf HandyMinis.app
mv "$APP" HandyMinis.app
APP="HandyMinis.app"
echo "已生成 $APP"
echo "运行: open $APP"
echo "快捷键: ⌘⇧C 打开历史，⌃⌘A 框选截图"

if [[ "${1:-}" == "run" ]]; then
  open "$APP"
fi
