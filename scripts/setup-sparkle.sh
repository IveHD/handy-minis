#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/sparkle
curl --fail --location --retry 3 --connect-timeout 20 --max-time 600 https://github.com/sparkle-project/Sparkle/releases/download/2.9.6/Sparkle-2.9.6.tar.xz -o .build/sparkle.tar.xz ||
  curl --fail --location --retry 3 --connect-timeout 20 --max-time 600 -H "Accept: application/octet-stream" https://api.github.com/repos/sparkle-project/Sparkle/releases/assets/517328209 -o .build/sparkle.tar.xz
echo "52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192  .build/sparkle.tar.xz" | shasum -a 256 -c -
tar -xJf .build/sparkle.tar.xz -C .build/sparkle
