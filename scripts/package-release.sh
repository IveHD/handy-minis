#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${APP_VERSION:?Set APP_VERSION}"
: "${APP_BUILD:?Set monotonically increasing APP_BUILD}"
: "${UPDATE_FEED_URL:?Set UPDATE_FEED_URL}"
: "${SPARKLE_PUBLIC_KEY:?Set SPARKLE_PUBLIC_KEY}"
: "${SIGN_ID:?Set Developer ID Application signing identity}"
: "${NOTARY_PROFILE:?Set notarytool Keychain profile}"
: "${DOWNLOAD_URL_PREFIX:?Set GitHub release download URL ending in /}"
export RELEASE_BUILD=1
./build.sh
# Sign nested Sparkle code before the containing application with hardened runtime.
find DeskKit.app/Contents/Frameworks -type f -perm +111 -print0 | while IFS= read -r -d '' binary; do
  if file "$binary" | grep -q 'Mach-O'; then
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$binary"
  fi
done
codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" DeskKit.app
codesign --verify --deep --strict DeskKit.app
release_dir="dist/${APP_VERSION}-${APP_BUILD}"
mkdir -p "$release_dir"
archive="$release_dir/DeskKit-${APP_VERSION}-${APP_BUILD}.zip"
ditto -c -k --sequesterRsrc --keepParent DeskKit.app "$archive"
xcrun notarytool submit "$archive" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple DeskKit.app
xcrun stapler validate DeskKit.app
ditto -c -k --sequesterRsrc --keepParent DeskKit.app "$archive"
.build/sparkle/bin/generate_appcast --download-url-prefix "$DOWNLOAD_URL_PREFIX" "$release_dir"
printf '发布文件已生成于 dist/。上传 ZIP 至 Release，上传 appcast.xml 至 Pages。\n'
