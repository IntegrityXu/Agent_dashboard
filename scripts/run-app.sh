#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Status Board.app"
if [[ ! -x "$APP/Contents/MacOS/StatusBoard" ]]; then "$ROOT/scripts/package-app.sh"; fi
open "$APP"
