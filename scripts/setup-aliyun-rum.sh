#!/bin/bash
set -euo pipefail

archive="${1:-}"
cd "$(dirname "$0")/.."
sdk_dir="$PWD/.build/aliyun-rum"
mkdir -p "$sdk_dir"
if [[ -z "$archive" ]]; then
  archive="$sdk_dir/AlibabaCloud_RUM_macOS.zip"
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 120 \
    https://rum-sdk.oss-cn-hangzhou.aliyuncs.com/native/AlibabaCloud_RUM_macOS.zip -o "$archive"
fi

expected=b837d135b16eb1ec087cfba8796be2425765cb39e16b161d663364135e59085e
actual="$(shasum -a 256 < "$archive")"
if [[ "${actual%% *}" != "$expected" ]]; then
  echo "阿里云 RUM macOS SDK 的 SHA-256 与已验证的 0.4.4 下载包不符。" >&2
  exit 1
fi
unzip -oq "$archive" 'AlibabaCloud_RUM_macOS_0.4.4/include/alibabacloud_rum.h' \
  'AlibabaCloud_RUM_macOS_0.4.4/lib/*/Release/*.dylib' -d "$sdk_dir"
