#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/.build/window-recovery"
mkdir -p "$OUT" "$ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache"
xcrun swift build --disable-sandbox --package-path "$ROOT/Packages/StatusBoardCore" \
  --scratch-path "$ROOT/.build/core" --cache-path "$ROOT/.build/swiftpm/cache" \
  --config-path "$ROOT/.build/swiftpm/config" --security-path "$ROOT/.build/swiftpm/security" \
  --manifest-cache local
python3 - "$ROOT/StatusBoard/App/StatusBoardApp.swift" "$OUT/AppUnderTest.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
assert source.count('@main\n') == 1
Path(sys.argv[2]).write_text(source.replace('@main\n', '', 1))
PY
APP_SOURCES=("$OUT/AppUnderTest.swift")
for source in "$ROOT/StatusBoard/App/"*.swift; do
  if [[ "$source" != "$ROOT/StatusBoard/App/StatusBoardApp.swift" ]]; then APP_SOURCES+=("$source"); fi
done
DEBUG="$ROOT/.build/core/debug"
# Use the current build manifest: *.o can include deleted sources from an
# earlier incremental build and silently pull obsolete implementations back in.
python3 - "$DEBUG" "$OUT/objects.txt" <<'PY'
import json
from pathlib import Path
import sys
debug = Path(sys.argv[1])
objects = []
for target in ('StatusBoardCore', 'StatusBoardDesktop'):
    outputs = json.loads((debug / (target + '.build') / 'output-file-map.json').read_text())
    objects.extend(value['object'] for value in outputs.values() if 'object' in value)
objects.append(str(debug / 'StatusBoardSQLite.build' / 'SQLite.c.o'))
Path(sys.argv[2]).write_text('\n'.join(objects) + '\n')
PY
xcrun swiftc -parse-as-library -swift-version 6 -module-cache-path "$ROOT/.build/module-cache" \
  -I "$DEBUG/Modules" -I "$ROOT/Packages/StatusBoardCore/Sources/StatusBoardSQLite/include" "${APP_SOURCES[@]}" "$ROOT/Probes/WindowRecoveryCheck/main.swift" \
  -Xlinker -filelist -Xlinker "$OUT/objects.txt" \
  -o "$OUT/WindowRecoveryCheck"
cp "$ROOT/StatusBoard/Resources/joker_right.png" "$OUT/joker_right.png"
cp "$ROOT/StatusBoard/Resources/crown.png" "$OUT/crown.png"
"$OUT/WindowRecoveryCheck" --render-design-cases
