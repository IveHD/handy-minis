#!/bin/bash
set -euo pipefail
: "${1:?Usage: scripts/download-stats.sh OWNER/REPO}"
gh api --paginate "repos/$1/releases" --jq '.[] | .tag_name as $version | .assets[] | [$version, .name, .download_count] | @tsv'
