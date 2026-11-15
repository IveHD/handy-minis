# Sourced by the build scripts.
swift_build="$PWD/.build/screensnap"
swift_cache="$swift_build/module-cache"
mkdir -p "$swift_cache"

# Some Command Line Tools upgrades leave two copies of the SwiftBridging module map.
# Hide the duplicate from this build only.
clang_flags=()
swift_include="$(dirname "$(xcrun --find swiftc)")/../include/swift"
if [[ -f "$swift_include/module.modulemap" && -f "$swift_include/bridging.modulemap" ]] &&
   grep -q "^module SwiftBridging " "$swift_include/module.modulemap" &&
   grep -q "^module SwiftBridging " "$swift_include/bridging.modulemap"; then
  python3 - "$swift_include/bridging.modulemap" "$swift_build" <<'PYTHON'
import json
import sys
from pathlib import Path

duplicate, build = map(Path, sys.argv[1:])
build = build.resolve()
empty = build / "empty.modulemap"
empty.touch()
(build / "overlay.json").write_text(json.dumps({
    "version": 0,
    "roots": [{
        "type": "file",
        "name": str(duplicate.resolve()),
        "external-contents": str(empty),
    }],
}))
PYTHON
  clang_flags=(-explicit-module-build -Xcc -ivfsoverlay -Xcc "$swift_build/overlay.json")
fi
