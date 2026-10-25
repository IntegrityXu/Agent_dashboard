#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
xcrun swift test --disable-sandbox --package-path "$ROOT/Packages/StatusBoardCore" \
  --scratch-path "$ROOT/.build/core" --cache-path "$ROOT/.build/swiftpm/cache" \
  --config-path "$ROOT/.build/swiftpm/config" --security-path "$ROOT/.build/swiftpm/security" \
  --manifest-cache local "$@"
