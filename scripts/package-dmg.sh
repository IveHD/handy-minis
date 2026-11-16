#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

app="HandyMinis.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
output="dist/HandyMinis-${version}-macOS-Universal.dmg"
mkdir -p .build dist
work="$(mktemp -d "$PWD/.build/handyminis-dmg.XXXXXX")"
staging="$work/staging"
mount="$work/mount"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then
    hdiutil detach "$mount" || return
  fi
  rm -rf "$work"
}
trap cleanup EXIT

mkdir "$staging" "$mount"
ditto "$app" "$staging/$app"
ln -s /Applications "$staging/Applications"
cp "$app/Contents/Resources/AppIcon.icns" "$staging/.VolumeIcon.icns"

hdiutil create -fs HFS+ -volname HandyMinis -srcfolder "$staging" -format UDRW "$work/install.dmg"
hdiutil attach -nobrowse -mountpoint "$mount" "$work/install.dmg"
mounted=1
# Set the flag on the volume root so it survives compression and distribution.
xcrun SetFile -a C "$mount"
hdiutil detach "$mount"
mounted=0
hdiutil convert "$work/install.dmg" -ov -format UDZO -o "$output"
# Finder stores the file icon as metadata. The volume icon above travels with the DMG.
clang -fobjc-arc -framework AppKit scripts/set-file-icon.m -o "$work/set-file-icon"
if ! "$work/set-file-icon" "$PWD/$app/Contents/Resources/AppIcon.icns" "$PWD/$output"; then
  echo "未能设置本地 DMG 文件图标，安装卷图标已写入。" >&2
fi
(cd dist && shasum -a 256 "$(basename "$output")" > SHA256SUMS.txt)
