#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

tag="${1:-}"
if [[ ! "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "用法：bash scripts/publish-sparkle-feed.sh v<主版本>.<次版本>.<修订版本>" >&2
  exit 1
fi

sparkle="$PWD/.build/sparkle/bin"
if [[ ! -x "$sparkle/generate_appcast" ]]; then
  scripts/setup-sparkle.sh
fi

appcast="$PWD/docs/appcast.xml"
download_url="https://github.com/IveHD/handy-minis/releases/download/$tag"
archive="HandyMinis-${tag#v}-macOS-Universal.dmg"
work="$(mktemp -d "$PWD/.build/sparkle-release.XXXXXX")"
mount="$work/mount"
mounted=0
cleanup() {
  if [[ "$mounted" == 1 ]]; then
    hdiutil detach "$mount" >/dev/null || return
  fi
  rm -rf "$work"
}
trap cleanup EXIT

curl --fail --silent --show-error --location --retry 3 "$download_url/$archive" -o "$work/$archive"
curl --fail --silent --show-error --location --retry 3 "$download_url/SHA256SUMS.txt" -o "$work/SHA256SUMS.txt"
(cd "$work" && shasum -a 256 -c SHA256SUMS.txt)

mkdir "$mount"
hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$work/$archive" >/dev/null
mounted=1
plist="$mount/HandyMinis.app/Contents/Info.plist"
public_key="$("$sparkle/generate_keys" -p)"
if [[ -z "$public_key" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist")" != "$public_key" ||
      "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$plist")" != "https://ivehd.github.io/handy-minis/appcast.xml" ]]; then
  echo "该 DMG 的更新地址或公钥与 HandyMinis 发布配置不匹配。" >&2
  exit 1
fi
hdiutil detach "$mount" >/dev/null
mounted=0
rmdir "$mount"

"$sparkle/generate_appcast" --download-url-prefix "$download_url/" "$work"

python3 - "$work/appcast.xml" "$appcast" "$download_url/$archive" "$tag" <<'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

generated, published = map(Path, sys.argv[1:3])
archive_url, tag = sys.argv[3:]
namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

def latest_item(path):
    return ET.parse(path).find("./channel/item")

item = latest_item(generated)
enclosure = item.find("enclosure") if item is not None else None
if (
    enclosure is None
    or enclosure.get("url") != archive_url
    or not enclosure.get(f"{{{namespace['sparkle']}}}edSignature")
    or item.findtext("sparkle:shortVersionString", namespaces=namespace) != tag[1:]
):
    sys.exit("生成的 appcast 缺少预期的签名更新条目。")

build = int(item.findtext("sparkle:version", namespaces=namespace))
if published.exists():
    current = latest_item(published)
    if current is not None:
        current_build = int(current.findtext("sparkle:version", namespaces=namespace))
        if build <= current_build:
            sys.exit(f"新构建号 {build} 必须大于现有构建号 {current_build}。")
PY

mv "$work/appcast.xml" "$appcast"
echo "已生成 docs/appcast.xml。将它提交并推送到 GitHub Pages 的发布分支。"
