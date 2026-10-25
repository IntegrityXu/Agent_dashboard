#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-Debug}"
case "$CONFIG" in Debug|Release) ;; *) echo 'Expected Debug or Release' >&2; exit 64;; esac
xcodebuild -project "$ROOT/StatusBoard.xcodeproj" -scheme StatusBoard \
  -configuration "$CONFIG" -destination 'platform=macOS' \
  -derivedDataPath "$ROOT/.build/xcode" -clonedSourcePackagesDirPath "$ROOT/.build/packages" \
  build CODE_SIGNING_ALLOWED=NO
APP="$ROOT/.build/xcode/Build/Products/$CONFIG/StatusBoard.app"
test -x "$APP/Contents/MacOS/StatusBoard"
echo "$APP"
