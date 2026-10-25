#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/.build/lens-check"
mkdir -p "$OUT"
python3 - "$ROOT/Archive/DesktopLens/DesktopLensCheck/DesktopLens.swift" "$OUT/lens.metal" <<'PY'
from pathlib import Path
import sys
source=Path(sys.argv[1]).read_text()
shader=source.split('private static let shader = #"""\n',1)[1].split('    """#',1)[0]
Path(sys.argv[2]).write_text(shader)
PY
xcrun swiftc "$ROOT/Archive/DesktopLens/DesktopLensCheck/main.swift" -o "$OUT/check"
"$OUT/check" "$OUT/lens.metal"
